import 'package:opennutritracker/core/data/repository/body_measurement_log_repository.dart';

class DeleteBodyMeasurementLogUsecase {
  final BodyMeasurementLogRepository _repository;

  DeleteBodyMeasurementLogUsecase(this._repository);

  Future<void> deleteEntry(DateTime date) => _repository.deleteEntry(date);
}
