import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/dbo/body_measurement_log_dbo.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';

class BodyMeasurementLogDataSource {
  final HiveDBProvider _db;

  BodyMeasurementLogDataSource(this._db);

  Box<BodyMeasurementLogDBO> get _box => _db.bodyMeasurementLogBox;

  Future<void> addEntry(BodyMeasurementLogDBO entry) async {
    await _box.put(entry.date.toParsedDay(), entry);
  }

  Future<void> addAllEntries(List<BodyMeasurementLogDBO> entries) async {
    await _box.putAll({
      for (final entry in entries) entry.date.toParsedDay(): entry,
    });
  }

  Future<List<BodyMeasurementLogDBO>> allEntries() async =>
      _box.values.toList();

  Future<List<BodyMeasurementLogDBO>> entriesInRange(
    DateTime from,
    DateTime to,
  ) async {
    return _box.values
        .where((entry) => !entry.date.isBefore(from) && !entry.date.isAfter(to))
        .toList();
  }

  Future<BodyMeasurementLogDBO?> getEntry(DateTime date) async =>
      _box.get(date.toParsedDay());

  Future<void> deleteEntry(DateTime date) async {
    await _box.delete(date.toParsedDay());
  }
}
