import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/data_source/custom_activity_template_dbo.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_dbo.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/data/dbo/body_measurement_log_dbo.dart';
import 'package:opennutritracker/core/data/dbo/fasting_session_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/profile_dbo.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_dbo.dart';
import 'package:opennutritracker/core/data/dbo/water_intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/weight_log_dbo.dart';
import 'package:opennutritracker/hive_registrar.g.dart';

/// Owns every Hive box the app uses.
///
/// Boxes fall into two groups. The **global** ones are shared across every
/// profile: the Open Food Facts response cache, the profile registry, the
/// app-wide settings (theme, language, units, notifications, ...), and the
/// reusable content libraries (custom meals, recipes, activity templates).
/// The **per-profile** ones are each profile's own private data — the meal,
/// activity, weight, water and fasting logs, tracked-day totals, the user's
/// body stats, and the personal nutrition goals in ConfigBox.
///
/// Per-profile boxes are named by appending the active profile's
/// `boxSuffix`. The first profile carries an empty suffix, so it resolves
/// to the original box names already on disk; that is what lets an
/// existing user keep all their data untouched when they upgrade into a
/// multi-profile build. Switching profiles closes the current set and
/// opens the target's, so the per-profile getters always hand back the
/// boxes belonging to whoever is active right now.
class HiveDBProvider extends ChangeNotifier {
  String dataset = '';
  String? restoredActiveProfileId;
  bool restorePending = false;
  late String documentsDirectory;
  String physicalBoxName(String base, [String suffix = '']) =>
      '${dataset.isEmpty ? '' : '${dataset}_'}${boxNameFor(base, suffix)}';

  Future<void> activateRestoredDataset(String name, String profileId) async {
    final pointer = File('$documentsDirectory/stable_dataset.json');
    final pending = File('${pointer.path}.pending');
    await pending.writeAsString(
      jsonEncode({'dataset': name, 'activeProfileId': profileId}),
      flush: true,
    );
    await pending.rename(pointer.path);
    restorePending = true;
  }

  Future<void> _saveDatasetProfile(String id) async {
    if (dataset.isEmpty || restorePending) return;
    final pointer = File('$documentsDirectory/stable_dataset.json');
    final pending = File('${pointer.path}.profile');
    await pending.writeAsString(
      jsonEncode({'dataset': dataset, 'activeProfileId': id}),
      flush: true,
    );
    await pending.rename(pointer.path);
  }

  static const configBoxName = 'ConfigBox';
  static const intakeBoxName = 'IntakeBox';
  static const userActivityBoxName = 'UserActivityBox';
  static const userBoxName = 'UserBox';
  static const trackedDayBoxName = 'TrackedDayBox';
  static const customMealBoxName = 'CustomMealBox';
  static const recipeBoxName = 'RecipeBox';
  static const cachedOffMealBoxName = 'CachedOffMealBox';
  // Sidecar to cachedOffMealBox: maps meal `code` -> millisSinceEpoch of
  // last "touch" (creation or user re-select). Used by the TTL sweep so
  // unused cache entries age out after 90 days.
  static const cachedOffMealTimestampsBoxName = 'CachedOffMealTimestampsBox';
  // #70 follow-up: saved Custom activity templates (name + typical kcal).
  static const customActivityTemplateBoxName = 'CustomActivityTemplateBox';
  static const weightLogBoxName = 'WeightLogBox';
  static const bodyMeasurementLogBoxName = 'BodyMeasurementLogBox';
  static const lifesumImportJournalBoxName = 'LifesumImportJournalBox';
  static const dailyStepsBoxName = 'DailyStepsBox';
  static const cycleBoxName = 'CycleBox';
  // #32: per-entry water intake log keyed by uuid; one row per sip so the
  // dialog's "undo last" can roll a single entry back without losing the
  // rest of the day.
  static const waterIntakeBoxName = 'WaterIntakeBox';
  // #84: persisted fasting sessions, one record per start. The data layer
  // intentionally keeps cancelled and completed sessions side by side with no
  // success/failure label on the record — see `FastingSessionDBO`.
  static const fastingBoxName = 'FastingBox';
  // #471: registry of profiles. Global — shared across every profile so
  // the app can enumerate and switch profiles before any one of them is
  // active.
  static const profileBoxName = 'ProfileBox';
  // #471: app-wide settings shared across every profile (theme, language,
  // units, notifications, anonymous-data consent, view preferences, ...).
  // Only the genuinely personal nutrition goals live in the per-profile
  // ConfigBox; everything else is read from here.
  static const appConfigBoxName = 'AppConfigBox';

  // The base names of every per-profile box, used when opening, closing,
  // or deleting a profile's box-set. The custom-meal, recipe and
  // activity-template libraries are deliberately NOT here — they are shared
  // content (see the global boxes below), not per-profile data.
  static const perProfileBoxNames = <String>[
    configBoxName,
    intakeBoxName,
    userActivityBoxName,
    userBoxName,
    trackedDayBoxName,
    weightLogBoxName,
    bodyMeasurementLogBoxName,
    lifesumImportJournalBoxName,
    dailyStepsBoxName,
    cycleBoxName,
    waterIntakeBoxName,
    fastingBoxName,
  ];

  // Global boxes — opened once, never closed on a profile switch.
  late final Box<MealDBO> cachedOffMealBox;
  late final Box<int> cachedOffMealTimestampsBox;
  late final Box<ProfileDBO> profileBox;
  // Backed by a getter so a scoped provider (cross-profile writes) can point
  // it at the real shared box without going through initHiveDB.
  late final Box<ConfigDBO> _appConfigBox;
  Box<ConfigDBO> get appConfigBox => _appConfigBox;
  // Shared content libraries — reusable definitions, not personal logs, so
  // every profile draws from the same set.
  late final Box<MealDBO> customMealBox;
  late final Box<RecipeDBO> recipeBox;
  late final Box<CustomActivityTemplateDBO> customActivityTemplateBox;

  // Per-profile boxes. Nullable rather than `late` so that a read during
  // the brief close/open window of a profile switch throws a descriptive
  // error through `_requireBox` instead of Hive's opaque closed-box error.
  Box<ConfigDBO>? _configBox;
  Box<IntakeDBO>? _intakeBox;
  Box<UserActivityDBO>? _userActivityBox;
  Box<UserDBO>? _userBox;
  Box<TrackedDayDBO>? _trackedDayBox;
  Box<WeightLogDBO>? _weightLogBox;
  Box<BodyMeasurementLogDBO>? _bodyMeasurementLogBox;
  Box<String>? _lifesumImportJournalBox;
  Box<String>? _dailyStepsBox;
  Box<String>? _cycleBox;
  Box<String> get cycleBox => _requireBox(_cycleBox, cycleBoxName);
  Box<WaterIntakeDBO>? _waterIntakeBox;
  Box<FastingSessionDBO>? _fastingBox;

  late final HiveAesCipher _cipher;
  String _activeProfileId = '';
  String _activeBoxSuffix = '';
  int _activeProfileGeneration = 0;
  bool _switching = false;

  String get activeProfileId => _activeProfileId;
  int get activeProfileGeneration => _activeProfileGeneration;

  Box<ConfigDBO> get configBox => _requireBox(_configBox, configBoxName);
  Box<IntakeDBO> get intakeBox => _requireBox(_intakeBox, intakeBoxName);
  Box<UserActivityDBO> get userActivityBox =>
      _requireBox(_userActivityBox, userActivityBoxName);
  Box<UserDBO> get userBox => _requireBox(_userBox, userBoxName);
  Box<TrackedDayDBO> get trackedDayBox =>
      _requireBox(_trackedDayBox, trackedDayBoxName);
  Box<WeightLogDBO> get weightLogBox =>
      _requireBox(_weightLogBox, weightLogBoxName);
  Box<BodyMeasurementLogDBO> get bodyMeasurementLogBox =>
      _requireBox(_bodyMeasurementLogBox, bodyMeasurementLogBoxName);
  Box<String> get lifesumImportJournalBox =>
      _requireBox(_lifesumImportJournalBox, lifesumImportJournalBoxName);
  Box<String> get dailyStepsBox =>
      _requireBox(_dailyStepsBox, dailyStepsBoxName);
  Box<WaterIntakeDBO> get waterIntakeBox =>
      _requireBox(_waterIntakeBox, waterIntakeBoxName);
  Box<FastingSessionDBO> get fastingBox =>
      _requireBox(_fastingBox, fastingBoxName);

  Box<T> _requireBox<T>(Box<T>? box, String name) {
    if (_switching) {
      throw StateError(
        'Tried to read "$name" while a profile switch was in progress.',
      );
    }
    if (box == null) {
      throw StateError(
        'Tried to read "$name" before any profile box-set was opened.',
      );
    }
    return box;
  }

  /// Resolves a per-profile box name for a given profile suffix. The
  /// default profile (`suffix == ''`) keeps the legacy unsuffixed name.
  static String boxNameFor(String base, String suffix) =>
      suffix.isEmpty ? base : '${base}_$suffix';

  /// Opens the global boxes and registers all adapters. Per-profile
  /// boxes are opened separately via [openProfileBoxes] once the caller
  /// (the locator's startup migration) has decided which profile is
  /// active.
  Future<void> initHiveDB(
    Uint8List encryptionKey, {
    bool registerAdapters = true,
  }) async {
    _cipher = HiveAesCipher(encryptionKey);
    await Hive.initFlutter();
    documentsDirectory = (await getApplicationDocumentsDirectory()).path;
    final pointer = File('$documentsDirectory/stable_dataset.json');
    if (await pointer.exists()) {
      final saved =
          jsonDecode(await pointer.readAsString()) as Map<String, dynamic>;
      final name = saved['dataset'] as String;
      if (!RegExp(r'^restore_[a-zA-Z0-9_]+$').hasMatch(name)) {
        throw const FormatException('Invalid dataset');
      }
      dataset = name;
      restoredActiveProfileId = saved['activeProfileId'] as String;
    }
    UserImageStorage.setDocumentsRoot(
      dataset.isEmpty ? documentsDirectory : '$documentsDirectory/$dataset',
    );
    // Delegate to the generated registrar so any new DBO type added to
    // the project is registered automatically on the next `just build`.
    // Registering by hand had drifted out of sync — `CaloriesProfileDBO`
    // (#7 on UserDBO) was missing, causing every save with a non-null
    // hormone profile to throw, which the previous broken async chains
    // swallowed silently. Result: profile reset to null on app relaunch.
    if (registerAdapters) Hive.registerAdapters();

    profileBox = await Hive.openBox(
      physicalBoxName(profileBoxName),
      encryptionCipher: _cipher,
    );
    cachedOffMealBox = await Hive.openBox(
      physicalBoxName(cachedOffMealBoxName),
      encryptionCipher: _cipher,
    );
    cachedOffMealTimestampsBox = await Hive.openBox(
      physicalBoxName(cachedOffMealTimestampsBoxName),
      encryptionCipher: _cipher,
    );
    _appConfigBox = await Hive.openBox(
      physicalBoxName(appConfigBoxName),
      encryptionCipher: _cipher,
    );
    customMealBox = await Hive.openBox(
      physicalBoxName(customMealBoxName),
      encryptionCipher: _cipher,
    );
    recipeBox = await Hive.openBox(
      physicalBoxName(recipeBoxName),
      encryptionCipher: _cipher,
    );
    customActivityTemplateBox = await Hive.openBox(
      physicalBoxName(customActivityTemplateBoxName),
      encryptionCipher: _cipher,
    );
  }

  /// Opens the per-profile box-set for [profileId] / [boxSuffix] and
  /// marks it active. Used once at startup for the active profile.
  Future<void> openProfileBoxes(String profileId, String boxSuffix) async {
    _activeProfileId = profileId;
    _activeBoxSuffix = boxSuffix;
    await _openActiveProfileBoxes();
    _activeProfileGeneration++;
    await _saveDatasetProfile(profileId);
  }

  /// Closes the current profile's box-set and opens [profileId]'s. The
  /// `_switching` guard makes any racing read fail loudly rather than
  /// hitting a half-open box.
  Future<void> switchProfile(String profileId, String boxSuffix) async {
    if (profileId == _activeProfileId) return;
    _switching = true;
    _activeProfileGeneration++;
    try {
      await _closeActiveProfileBoxes();
      _activeProfileId = profileId;
      _activeBoxSuffix = boxSuffix;
      await _openActiveProfileBoxes();
    } finally {
      _switching = false;
    }
    await _saveDatasetProfile(profileId);
    notifyListeners();
  }

  Future<void> _openActiveProfileBoxes() async {
    final suffix = _activeBoxSuffix;
    _configBox = await Hive.openBox(
      physicalBoxName(configBoxName, suffix),
      encryptionCipher: _cipher,
    );
    _intakeBox = await Hive.openBox(
      physicalBoxName(intakeBoxName, suffix),
      encryptionCipher: _cipher,
    );
    _userActivityBox = await Hive.openBox(
      physicalBoxName(userActivityBoxName, suffix),
      encryptionCipher: _cipher,
    );
    _userBox = await Hive.openBox(
      physicalBoxName(userBoxName, suffix),
      encryptionCipher: _cipher,
    );
    _trackedDayBox = await Hive.openBox(
      physicalBoxName(trackedDayBoxName, suffix),
      encryptionCipher: _cipher,
    );
    _weightLogBox = await Hive.openBox(
      physicalBoxName(weightLogBoxName, suffix),
      encryptionCipher: _cipher,
    );
    _bodyMeasurementLogBox = await Hive.openBox(
      physicalBoxName(bodyMeasurementLogBoxName, suffix),
      encryptionCipher: _cipher,
    );
    _lifesumImportJournalBox = await Hive.openBox(
      physicalBoxName(lifesumImportJournalBoxName, suffix),
      encryptionCipher: _cipher,
    );
    _waterIntakeBox = await Hive.openBox(
      physicalBoxName(waterIntakeBoxName, suffix),
      encryptionCipher: _cipher,
    );
    _fastingBox = await Hive.openBox(
      physicalBoxName(fastingBoxName, suffix),
      encryptionCipher: _cipher,
    );
    _dailyStepsBox = await Hive.openBox(
      physicalBoxName(dailyStepsBoxName, suffix),
      encryptionCipher: _cipher,
    );
    _cycleBox = await Hive.openBox(
      physicalBoxName(cycleBoxName, suffix),
      encryptionCipher: _cipher,
    );
  }

  Future<void> _closeActiveProfileBoxes() async {
    await Future.wait([
      if (_configBox != null) _configBox!.close(),
      if (_intakeBox != null) _intakeBox!.close(),
      if (_userActivityBox != null) _userActivityBox!.close(),
      if (_userBox != null) _userBox!.close(),
      if (_trackedDayBox != null) _trackedDayBox!.close(),
      if (_weightLogBox != null) _weightLogBox!.close(),
      if (_bodyMeasurementLogBox != null) _bodyMeasurementLogBox!.close(),
      if (_lifesumImportJournalBox != null) _lifesumImportJournalBox!.close(),
      if (_dailyStepsBox != null) _dailyStepsBox!.close(),
      if (_cycleBox != null) _cycleBox!.close(),
      if (_waterIntakeBox != null) _waterIntakeBox!.close(),
      if (_fastingBox != null) _fastingBox!.close(),
    ]);
    _configBox = null;
    _intakeBox = null;
    _userActivityBox = null;
    _userBox = null;
    _trackedDayBox = null;
    _weightLogBox = null;
    _bodyMeasurementLogBox = null;
    _lifesumImportJournalBox = null;
    _dailyStepsBox = null;
    _cycleBox = null;
    _waterIntakeBox = null;
    _fastingBox = null;
  }

  /// Opens (or returns the already-open) box for an arbitrary profile
  /// suffix, using the shared encryption cipher. Used to read/write a
  /// profile other than the active one — e.g. copying a meal into another
  /// profile — without disturbing the active box-set.
  Future<Box<E>> openScopedBox<E>(String baseName, String boxSuffix) {
    return Hive.openBox<E>(
      physicalBoxName(baseName, boxSuffix),
      encryptionCipher: _cipher,
    );
  }

  /// Closes a box previously opened via [openScopedBox]. Callers that open a
  /// scoped box-set for a one-off operation (e.g. copying an intake into a
  /// profile that isn't active) should close it afterwards so it doesn't
  /// stay resident — mirroring how switching profiles closes the outgoing
  /// box-set. A no-op if the box isn't open.
  Future<void> closeScopedBox<E>(String baseName, String boxSuffix) async {
    final name = physicalBoxName(baseName, boxSuffix);
    if (Hive.isBoxOpen(name)) {
      await Hive.box<E>(name).close();
    }
  }

  /// Permanently removes the box-set belonging to [boxSuffix] from disk.
  /// The profile must not be active (close its boxes by switching away
  /// first). The global cache and profile-registry boxes are never
  /// touched here.
  Future<void> deleteProfileBoxes(String boxSuffix) async {
    for (final base in perProfileBoxNames) {
      await Hive.deleteBoxFromDisk(physicalBoxName(base, boxSuffix));
    }
  }

  Future<Box<dynamic>> openDataBox(
    String base, {
    String suffix = '',
    String? namespace,
  }) {
    final prefix = namespace ?? dataset;
    final name =
        '${prefix.isEmpty ? '' : '${prefix}_'}${boxNameFor(base, suffix)}';
    return switch (base) {
      'ConfigBox' => Hive.openBox<ConfigDBO>(name, encryptionCipher: _cipher),
      'IntakeBox' => Hive.openBox<IntakeDBO>(name, encryptionCipher: _cipher),
      'UserActivityBox' => Hive.openBox<UserActivityDBO>(
        name,
        encryptionCipher: _cipher,
      ),
      'UserBox' => Hive.openBox<UserDBO>(name, encryptionCipher: _cipher),
      'TrackedDayBox' => Hive.openBox<TrackedDayDBO>(
        name,
        encryptionCipher: _cipher,
      ),
      'WeightLogBox' => Hive.openBox<WeightLogDBO>(
        name,
        encryptionCipher: _cipher,
      ),
      'BodyMeasurementLogBox' => Hive.openBox<BodyMeasurementLogDBO>(
        name,
        encryptionCipher: _cipher,
      ),
      'LifesumImportJournalBox' => Hive.openBox<String>(
        name,
        encryptionCipher: _cipher,
      ),
      'DailyStepsBox' => Hive.openBox<String>(name, encryptionCipher: _cipher),
      'WaterIntakeBox' => Hive.openBox<WaterIntakeDBO>(
        name,
        encryptionCipher: _cipher,
      ),
      'FastingBox' => Hive.openBox<FastingSessionDBO>(
        name,
        encryptionCipher: _cipher,
      ),
      'CycleBox' => Hive.openBox<String>(name, encryptionCipher: _cipher),
      'ProfileBox' => Hive.openBox<ProfileDBO>(name, encryptionCipher: _cipher),
      'AppConfigBox' => Hive.openBox<ConfigDBO>(
        name,
        encryptionCipher: _cipher,
      ),
      'CustomMealBox' => Hive.openBox<MealDBO>(name, encryptionCipher: _cipher),
      'RecipeBox' => Hive.openBox<RecipeDBO>(name, encryptionCipher: _cipher),
      'CustomActivityTemplateBox' => Hive.openBox<CustomActivityTemplateDBO>(
        name,
        encryptionCipher: _cipher,
      ),
      _ => throw ArgumentError('Unknown backup box'),
    };
  }

  static List<int> generateNewHiveEncryptionKey() => Hive.generateSecureKey();
}
