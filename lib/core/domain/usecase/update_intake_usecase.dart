import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';

class UpdateIntakeUsecase {
  final IntakeRepository _intakeRepository;

  UpdateIntakeUsecase(this._intakeRepository);

  Future<IntakeEntity?> updateIntake(
    String intakeId,
    Map<String, dynamic> intakeFields,
  ) async {
    return await _intakeRepository.updateIntake(intakeId, intakeFields);
  }

  /// Saves the whole entry: its amount, meal slot and food snapshot. An
  /// entry that no longer exists is added back.
  Future<void> putIntake(IntakeEntity intake) async {
    await _intakeRepository.putIntake(intake);
  }
}
