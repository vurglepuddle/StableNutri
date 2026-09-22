import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';

/// Every write is held open until the test releases it.
class _SlowRepository extends Fake implements ConfigRepository {
  final pending = Completer<void>();

  @override
  Future<void> setConfigShowActivityTracking(bool show) => pending.future;
  @override
  Future<void> setConfigShowWaterTracking(bool show) => pending.future;
  @override
  Future<void> setConfigShowMealMacros(bool show) => pending.future;
  @override
  Future<void> setConfigShowMicronutrients(bool show) => pending.future;
  @override
  Future<void> setConfigUsesRangeGauge(bool usesRangeGauge) => pending.future;
  @override
  Future<void> setNotificationsEnabled(bool enabled) => pending.future;
  @override
  Future<void> setNotificationTime(int hour, int minute) => pending.future;
  @override
  Future<void> setSelectedLocale(String? locale) => pending.future;
  @override
  Future<void> setConfigDayStartOffsetMinutes(int minutes) => pending.future;
}

/// Settings reloads right after each save. A save that finished before its
/// write read back the old value, and the switch flipped back (Show Activity
/// Tracking), while Today, which reloaded later, showed the new one.
void main() {
  final saves = <String, Future<void> Function(AddConfigUsecase)>{
    'activity tracking': (u) => u.setConfigShowActivityTracking(false),
    'water tracking': (u) => u.setConfigShowWaterTracking(false),
    'meal macros': (u) => u.setConfigShowMealMacros(false),
    'micronutrients': (u) => u.setConfigShowMicronutrients(true),
    'range gauge': (u) => u.setConfigUsesRangeGauge(false),
    'notifications': (u) => u.setNotificationsEnabled(true),
    'notification time': (u) => u.setNotificationTime(9, 30),
    'language': (u) => u.setSelectedLocale('de'),
    'day start minutes': (u) => u.setConfigDayStartOffsetMinutes(30),
  };

  for (final MapEntry(key: name, value: save) in saves.entries) {
    test('saving $name waits for the write', () async {
      final repository = _SlowRepository();
      var done = false;
      final saving = save(
        AddConfigUsecase(repository),
      ).then((_) => done = true);

      await pumpEventQueue();
      expect(done, isFalse);

      repository.pending.complete();
      await saving;
      expect(done, isTrue);
    });
  }
}
