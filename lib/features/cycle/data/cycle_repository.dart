import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/notification_service.dart';
import 'package:opennutritracker/features/cycle/domain/cycle_data.dart';
import 'package:opennutritracker/generated/l10n.dart';

class CycleRepository extends ChangeNotifier {
  final HiveDBProvider db;
  final NotificationService notifications;
  S? _labels;
  Future<void> _reminders = Future.value();
  bool reminderFailed = false;
  bool _disposed = false;

  CycleRepository(this.db, this.notifications) {
    db.addListener(_changed);
  }

  CycleData get data {
    final raw = db.cycleBox.get('data');
    return raw == null ? const CycleData() : CycleData.decode(raw);
  }

  Future<void> save(CycleData next, {required int generation}) async {
    if (db.activeProfileGeneration != generation) {
      throw StateError('Profile changed');
    }
    next.validate(today: DateTime.now());
    final box = db.cycleBox;
    await box.put('data', next.encode());
    if (generation != db.activeProfileGeneration) return;
    _changed();
    await _reminders;
  }

  void useLabels(S labels) {
    _labels = labels;
    _schedule();
  }

  void _changed() {
    notifyListeners();
    _schedule();
  }

  void _schedule() {
    _reminders = _reminders
        .then((_) async {
          if (_disposed || db.restorePending) return;
          final state = data;
          final labels = _labels;
          DateTime? when;
          final start = state.expectedStart;
          if (state.enabled &&
              state.reminderEnabled &&
              start != null &&
              labels != null) {
            final candidate = DateTime(
              start.year,
              start.month,
              start.day - 3,
              state.reminderHour,
              state.reminderMinute,
            );
            if (candidate.isAfter(DateTime.now())) when = candidate;
          }
          await notifications.scheduleCycleReminder(
            when: when,
            title: labels?.cycleLabel ?? 'Cycle',
            body:
                labels?.cycleReminderBody ??
                'Your next cycle may start in about 3 days.',
          );
          reminderFailed = false;
        })
        .catchError((Object error) {
          reminderFailed = true;
        })
        .whenComplete(() {
          if (!_disposed) notifyListeners();
        });
  }

  @override
  void dispose() {
    _disposed = true;
    db.removeListener(_changed);
    super.dispose();
  }
}
