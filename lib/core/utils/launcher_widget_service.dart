import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Android owns the launcher UI and a durable outbox of water taps. Only
/// Flutter writes Hive, through the same use case as the in-app water flow.
/// IDs survive retries, so a process death between import and acknowledgement
/// cannot log a cup twice or open Hive from competing Flutter isolates.
class LauncherWidgetService {
  static const channel = MethodChannel('stable/quick_add_widget');
  static final _events = StreamController<void>.broadcast();
  static Stream<void> get events => _events.stream;
  static final _log = Logger('LauncherWidget');
  static final _imported = <String, Set<String>>{};
  static Future<List<String>>? _importing;
  static int revision = 0;

  /// What the widget was last sent. A refresh that changes nothing it shows,
  /// such as moving Today to another day, skips the redraw: Android redraws
  /// widgets on its main thread, which also delivers touches mid-swipe.
  static Map<String, Object?>? _lastPublished;
  static String? get activeProfileId =>
      supported && locator.isRegistered<GetProfilesUsecase>()
      ? locator<GetProfilesUsecase>().activeProfileId
      : null;
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void initialize() {
    if (!supported) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'actionAvailable' || call.method == 'waterQueued') {
        _events.add(null);
      }
    });
  }

  static Future<T?> _call<T>(String method, [Object? arguments]) async {
    if (!supported) return null;
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error, stack) {
      _log.warning('Launcher widget $method failed', error, stack);
      return null;
    }
  }

  static Future<String?> consumeAction() => _call<String>('consumeAction');

  static Future<void> discardProfile(String profileId) async {
    await _call<bool>('discardProfile', profileId);
    _imported.remove(profileId);
    _lastPublished = null;
  }

  static Future<List<String>> importWater() async {
    if (!supported || !locator.isRegistered<GetProfilesUsecase>()) return [];
    final currentImport = _importing;
    if (currentImport != null) return currentImport;
    final task = _importWater();
    _importing = task;
    try {
      return await task;
    } finally {
      _importing = null;
    }
  }

  static Future<List<String>> _importWater() async {
    final profile = locator<GetProfilesUsecase>().activeProfileId;
    final applied = <String>[];
    final entries = await _call<List<dynamic>>('pendingWater', profile) ?? [];
    for (final raw in entries) {
      final entry = Map<String, dynamic>.from(raw as Map);
      final id = entry['id'] as String;
      final amount = entry['amountMl'] as int;
      if (amount <= 0 || entry['profileId'] != profile) continue;
      await locator<AddWaterIntakeUsecase>().addEntry(
        WaterIntakeEntity(
          id: id,
          dateTime: DateTime.fromMillisecondsSinceEpoch(entry['time'] as int),
          amountMl: amount,
        ),
      );
      _imported.putIfAbsent(profile, () => {}).add(id);
      applied.add(id);
    }
    return applied;
  }

  static Future<void> publish({
    required String? expectedProfileId,
    required int expectedRevision,
    required List<String> appliedWaterIds,
    required ConfigEntity config,
    required DateTime day,
    required int waterMl,
    required int cupMl,
    required double foodKcal,
    required double exerciseKcal,
    ({int waterMl, double foodKcal, double exerciseKcal})? nextDay,
  }) async {
    if (!supported || !locator.isRegistered<GetProfilesUsecase>()) return;
    final profile = locator<GetProfilesUsecase>().getActiveProfile();
    if (profile == null ||
        profile.id != expectedProfileId ||
        revision != expectedRevision) {
      return;
    }
    final locale = basicLocaleListResolution([
      if (config.selectedLocale != null) Locale(config.selectedLocale!),
      WidgetsBinding.instance.platformDispatcher.locale,
    ], S.supportedLocales);
    final s = lookupS(locale);
    // Number and unit travel separately: the taller widget stacks them.
    String energy(double kcal) =>
        '${(config.usesKilojoules ? UnitCalc.kcalToKj(kcal) : kcal).round()}';
    final applied = appliedWaterIds;
    final snapshot = <String, Object?>{
      'profileId': profile.id,
      'profileName': profile.name,
      'locale': locale.toLanguageTag(),
      'accent': config.accentColor,
      'materialYou': config.useMaterialYou,
      'day': _dayKey(day),
      'offsetMinutes': config.dayStartOffsetTotalMinutes,
      'waterMl': waterMl,
      'cupMl': cupMl > 0 ? cupMl : 250,
      'waterLabel': s.trendsWaterLabel,
      'foodLabel': s.quickAddFoodLabel,
      'exerciseLabel': s.quickAddExerciseLabel,
      'foodAmount': energy(foodKcal),
      'exerciseAmount': energy(exerciseKcal),
      // The following day's totals, usually nothing yet. Android switches to
      // them at the day boundary while Stable is closed, instead of keeping
      // today's numbers until the app is next opened.
      if (nextDay != null) ...{
        'nextDay': _dayKey(DateTime(day.year, day.month, day.day + 1)),
        'nextWaterMl': nextDay.waterMl,
        'nextFoodAmount': energy(nextDay.foodKcal),
        'nextExerciseAmount': energy(nextDay.exerciseKcal),
      },
      'energyUnit': config.usesKilojoules ? s.kjLabel : s.kcalLabel,
      'waterUnits': pluralForms(s.localeName, s.widgetWaterUnit),
      // Food always stays, so the widget is never empty.
      'showWater': config.showWaterTracking,
      'showExercise': config.showActivityTracking,
      'addLabel': s.addLabel,
      'openLabel': s.widgetOpenStableLabel,
    };
    // Cups tapped on the widget are always acknowledged, even when the
    // totals already include them.
    if (applied.isEmpty &&
        const DeepCollectionEquality().equals(snapshot, _lastPublished)) {
      return;
    }
    final published = await _call<bool>('publish', {
      ...snapshot,
      'appliedWaterIds': applied,
    });
    if (published == true) {
      _imported[profile.id]?.removeAll(applied);
      _lastPublished = snapshot;
    }
  }

  static String _dayKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

  /// Every form of a plural [message], keyed by CLDR category (one, few,
  /// other...). The widget adds cups while Stable is closed, so it picks the
  /// form for its own total with Android's plural rules for the same locale.
  @visibleForTesting
  static Map<String, String> pluralForms(
    String locale,
    String Function(num count) message,
  ) {
    // Enough numbers to land in every category CLDR defines.
    const samples = <num>[0, 1, 2, 3, 5, 7, 11, 21, 100, 0.5, 1.5];
    final forms = <String, String>{};
    for (final count in samples) {
      final category = Intl.pluralLogic(
        count,
        locale: locale,
        zero: 'zero',
        one: 'one',
        two: 'two',
        few: 'few',
        many: 'many',
        other: 'other',
        useExplicitNumberCases: false,
      );
      forms.putIfAbsent(category, () => message(count));
    }
    return forms;
  }

  /// A switch invalidates displayed totals but retains taps for their owner.
  /// A profile wipe also discards that profile's pending water entries.
  static Future<void> clear({bool discardWater = false}) async {
    if (!supported || !locator.isRegistered<GetProfilesUsecase>()) return;
    revision++;
    _lastPublished = null;
    await _importing;
    final profile = locator<GetProfilesUsecase>().activeProfileId;
    await _call<bool>('clear', {
      'profileId': profile,
      'discardWater': discardWater,
      'appliedWaterIds': _imported[profile]?.toList() ?? <String>[],
    });
    _imported.remove(profile);
  }
}
