import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
    required int waterGoalMl,
    required int cupMl,
    required double foodKcal,
    required double exerciseKcal,
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
    final energyUnit = config.usesKilojoules ? s.kjLabel : s.kcalLabel;
    String energy(double kcal) =>
        '${(config.usesKilojoules ? UnitCalc.kcalToKj(kcal) : kcal).round()} $energyUnit';
    final applied = appliedWaterIds;
    final published = await _call<bool>('publish', {
      'profileId': profile.id,
      'profileName': profile.name,
      'locale': locale.toLanguageTag(),
      'theme': config.appTheme.name,
      'accent': config.accentColor,
      'materialYou': config.useMaterialYou,
      'day': '${day.year}-${day.month}-${day.day}',
      'offsetMinutes': config.dayStartOffsetTotalMinutes,
      'waterMl': waterMl,
      'waterGoalMl': waterGoalMl,
      'cupMl': cupMl > 0 ? cupMl : 250,
      'waterLabel': s.trendsWaterLabel,
      'foodLabel': s.quickAddFoodLabel,
      'exerciseLabel': s.quickAddExerciseLabel,
      'foodValue': energy(foodKcal),
      'foodStatus': s.suppliedLabel,
      'exerciseValue': energy(exerciseKcal),
      'exerciseStatus': s.burnedLabel,
      'addLabel': s.addLabel,
      'openLabel': s.widgetOpenStableLabel,
      'appliedWaterIds': applied,
    });
    if (published == true) _imported[profile.id]?.removeAll(applied);
  }

  /// A switch invalidates displayed totals but retains taps for their owner.
  /// A profile wipe also discards that profile's pending water entries.
  static Future<void> clear({bool discardWater = false}) async {
    if (!supported || !locator.isRegistered<GetProfilesUsecase>()) return;
    revision++;
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
