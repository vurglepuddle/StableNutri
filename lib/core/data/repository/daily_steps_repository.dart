import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/domain/entity/daily_steps.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';

class DailyStepsRepository {
  final HiveDBProvider _db;
  DailyStepsRepository(this._db);

  bool get autoImportEnabled => _db.dailyStepsBox.get('_autoImport') == 'true';

  DailySteps? forDay(DateTime day) {
    final value = _db.dailyStepsBox.get(day.toParsedDay());
    return value == null
        ? null
        : DailySteps.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  List<DailySteps> all() => _db.dailyStepsBox
      .toMap()
      .entries
      .where((entry) => !entry.key.toString().startsWith('_'))
      .map(
        (entry) => DailySteps.fromJson(
          jsonDecode(entry.value) as Map<String, dynamic>,
        ),
      )
      .toList();

  DailyStepsImport beginImport() => DailyStepsImport(_db);
}

/// Captured before permission/read/file-picker awaits. A stale operation cannot
/// follow a profile switch, even when the user switches away and back.
class DailyStepsImport {
  final HiveDBProvider _db;
  final String _profileId;
  final int _generation;
  final Box<String> _box;
  static final _saving = <Box<String>>{};

  DailyStepsImport(this._db)
    : _profileId = _db.activeProfileId,
      _generation = _db.activeProfileGeneration,
      _box = _db.dailyStepsBox;

  void requireCurrentProfile() {
    if (_db.activeProfileId != _profileId ||
        _db.activeProfileGeneration != _generation ||
        !_box.isOpen) {
      throw StateError('Profile changed. Open Health Connect again.');
    }
  }

  Future<void> setAutoImport(bool enabled) async {
    requireCurrentProfile();
    await _box.put('_autoImport', enabled.toString());
    requireCurrentProfile();
  }

  Future<int> save(List<DailySteps> totals) async {
    requireCurrentProfile();
    if (!_saving.add(_box)) {
      throw StateError('Step import already in progress.');
    }
    try {
      final updates = <String, String>{};
      for (final total in totals) {
        if (!total.isValid) throw const FormatException('Invalid daily steps');
        final previous = updates[total.dayKey] ?? _box.get(total.dayKey);
        if (previous != null) {
          final saved = DailySteps.fromJson(
            jsonDecode(previous) as Map<String, dynamic>,
          );
          // A slow/older read must not overwrite a newer read or restore.
          if (saved.readAt.isAfter(total.readAt) || saved == total) continue;
        }
        updates[total.dayKey] = jsonEncode(total.toJson());
      }
      requireCurrentProfile();
      // One box, absolute per-day values: retries cannot double the count and
      // no calorie, macro, activity or meal data is involved in this write.
      await _box.putAll(updates);
      await _box.flush();
      requireCurrentProfile();
      return updates.length;
    } finally {
      _saving.remove(_box);
    }
  }

  Future<void> removeDay(DateTime day) async {
    requireCurrentProfile();
    await _box.delete(day.toParsedDay());
    requireCurrentProfile();
  }
}
