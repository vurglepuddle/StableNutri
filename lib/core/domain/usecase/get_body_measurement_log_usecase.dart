import 'package:opennutritracker/core/data/repository/body_measurement_log_repository.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';

class GetBodyMeasurementLogUsecase {
  final BodyMeasurementLogRepository _repository;

  GetBodyMeasurementLogUsecase(this._repository);

  Future<List<BodyMeasurementLogEntity>> getAllEntries() =>
      _repository.getAllEntries();

  Future<List<BodyMeasurementLogEntity>> getEntriesInRange(
    DateTime from,
    DateTime to,
  ) => _repository.getEntriesInRange(from, to);

  Future<BodyMeasurementLogEntity?> getEntry(DateTime date) =>
      _repository.getEntry(date);
}
