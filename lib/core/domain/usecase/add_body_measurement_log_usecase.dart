import 'package:opennutritracker/core/data/repository/body_measurement_log_repository.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';

class AddBodyMeasurementLogUsecase {
  final BodyMeasurementLogRepository _repository;

  AddBodyMeasurementLogUsecase(this._repository);

  Future<void> addEntry(BodyMeasurementLogEntity entry) async {
    if (!entry.isValid) {
      throw ArgumentError.value(entry, 'entry', 'Invalid body measurements');
    }
    await _repository.addEntry(entry);
  }
}
