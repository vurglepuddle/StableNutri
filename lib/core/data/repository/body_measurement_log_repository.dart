import 'package:opennutritracker/core/data/data_source/body_measurement_log_data_source.dart';
import 'package:opennutritracker/core/data/dbo/body_measurement_log_dbo.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';

class BodyMeasurementLogRepository {
  final BodyMeasurementLogDataSource _dataSource;

  BodyMeasurementLogRepository(this._dataSource);

  Future<void> addEntry(BodyMeasurementLogEntity entry) =>
      _dataSource.addEntry(BodyMeasurementLogDBO.fromEntity(entry));

  Future<void> addAllEntries(List<BodyMeasurementLogDBO> entries) =>
      _dataSource.addAllEntries(entries);

  Future<List<BodyMeasurementLogEntity>> getAllEntries() async {
    final entries = await _dataSource.allEntries();
    return entries.map(BodyMeasurementLogEntity.fromDBO).toList();
  }

  Future<List<BodyMeasurementLogDBO>> getAllEntriesDBO() =>
      _dataSource.allEntries();

  Future<List<BodyMeasurementLogEntity>> getEntriesInRange(
    DateTime from,
    DateTime to,
  ) async {
    final entries = await _dataSource.entriesInRange(from, to);
    return entries.map(BodyMeasurementLogEntity.fromDBO).toList();
  }

  Future<BodyMeasurementLogEntity?> getEntry(DateTime date) async {
    final entry = await _dataSource.getEntry(date);
    return entry == null ? null : BodyMeasurementLogEntity.fromDBO(entry);
  }

  Future<void> deleteEntry(DateTime date) => _dataSource.deleteEntry(date);
}
