import 'dart:math' as math;

import 'package:opennutritracker/core/data/health/health_connect_service.dart';
import 'package:opennutritracker/core/data/repository/daily_steps_repository.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';

enum StepSyncResult {
  disabled,
  updated,
  empty,
  permissionRequired,
  unavailable,
  failed,
}

/// Called on app open/resume. Consent is per profile; Android permission alone
/// does not enable imports into other profiles. Automatic reads never prompt.
class HealthStepsSync {
  final HiveDBProvider db;
  final DailyStepsRepository repository;
  final HealthConnectService service;
  final Future<ConfigEntity> Function() getConfig;
  final DateTime Function() clock;
  final _running = <String, Future<StepSyncResult>>{};
  final _lastSuccess = <String, DateTime>{};

  HealthStepsSync({
    required this.db,
    required this.repository,
    required this.service,
    required this.getConfig,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  Future<StepSyncResult> sync({bool force = false}) {
    final key = '${db.activeProfileId}:${db.activeProfileGeneration}';
    final running = _running[key];
    if (running != null) return running;
    final operation = _sync(key, force);
    _running[key] = operation;
    return operation.whenComplete(() => _running.remove(key));
  }

  Future<StepSyncResult> _sync(String key, bool force) async {
    try {
      final target = repository.beginImport();
      if (!repository.autoImportEnabled) return StepSyncResult.disabled;
      final config = await getConfig();
      target.requireCurrentProfile();
      final offset = config.dayStartOffsetTotalMinutes;
      final now = clock();
      final day = DayBoundaryCalc.logicalDayOfMinutes(now, offset);
      // Throttle repeated reloads, but never carry the throttle across a day
      // boundary, changed boundary setting or changed active profile.
      final throttleKey = '$key:$offset:${day.toIso8601String()}';
      final previous = _lastSuccess[throttleKey];
      if (!force &&
          previous != null &&
          now.difference(previous) >= Duration.zero &&
          now.difference(previous) < const Duration(minutes: 15)) {
        return StepSyncResult.updated;
      }
      if (await service.status().timeout(const Duration(seconds: 3)) !=
          'available') {
        return StepSyncResult.unavailable;
      }
      target.requireCurrentProfile();
      if (!await service.hasReadPermission().timeout(
        const Duration(seconds: 3),
      )) {
        return StepSyncResult.permissionRequired;
      }
      target.requireCurrentProfile();
      final savedDays = repository.all();
      var days = 7;
      if (savedDays.isNotEmpty) {
        final latest = savedDays
            .map((row) => row.day)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        final gap = DateTime.utc(day.year, day.month, day.day)
            .difference(DateTime.utc(latest.year, latest.month, latest.day))
            .inDays;
        days = math.max(7, math.min(30, gap + 1));
      }
      final totals = await service
          .readRecentStepTotals(offsetMinutes: offset, days: days)
          .timeout(const Duration(seconds: 10));
      target.requireCurrentProfile();
      // The user may have disabled import or changed the day boundary while
      // Android was responding. Do not commit an obsolete request.
      if (!repository.autoImportEnabled) return StepSyncResult.disabled;
      final currentConfig = await getConfig();
      target.requireCurrentProfile();
      if (currentConfig.dayStartOffsetTotalMinutes != offset) {
        return StepSyncResult.failed;
      }
      await target.save(totals);
      _lastSuccess.clear();
      _lastSuccess[throttleKey] = now;
      return totals.isEmpty ? StepSyncResult.empty : StepSyncResult.updated;
    } catch (_) {
      // A health-provider failure must not stop the food diary from loading.
      // Deliberately do not log health records or platform exception payloads.
      return StepSyncResult.failed;
    }
  }
}
