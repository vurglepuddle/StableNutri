import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';

class GetIntakeUsecase {
  final IntakeRepository _intakeRepository;

  GetIntakeUsecase(this._intakeRepository);

  Future<List<IntakeEntity>> _getIntakeByDay(
    IntakeTypeEntity type,
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async {
    return await _intakeRepository.getIntakeByDateAndType(
      type,
      day,
      dayStartOffsetHours: dayStartOffsetHours,
      dayStartOffsetMinutes: dayStartOffsetMinutes,
    );
  }

  // #139: callers pass [dayStartOffsetHours] (and, since the follow-up,
  // [dayStartOffsetMinutes]) when they have the user's configured boundary.
  // Both default to 0 so every existing caller keeps wall-clock-midnight
  // behaviour exactly the same.
  //
  // The getToday... reads resolve the boundary before querying, because the
  // query takes a day *label*: handing it a raw DateTime.now() asks for the
  // wall-clock date, which between midnight and the boundary is not the
  // logical day the user is still in.
  Future<List<IntakeEntity>> getBreakfastIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => await _getIntakeByDay(
    IntakeTypeEntity.breakfast,
    day,
    dayStartOffsetHours: dayStartOffsetHours,
    dayStartOffsetMinutes: dayStartOffsetMinutes,
  );

  Future<List<IntakeEntity>> getTodayBreakfastIntake({
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => getBreakfastIntakeByDay(
    DayBoundaryCalc.currentLogicalDayLabel(
      dayStartOffsetHours,
      dayStartOffsetMinutes,
    ),
    dayStartOffsetHours: dayStartOffsetHours,
    dayStartOffsetMinutes: dayStartOffsetMinutes,
  );

  Future<List<IntakeEntity>> getLunchIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => await _getIntakeByDay(
    IntakeTypeEntity.lunch,
    day,
    dayStartOffsetHours: dayStartOffsetHours,
    dayStartOffsetMinutes: dayStartOffsetMinutes,
  );

  Future<List<IntakeEntity>> getTodayLunchIntake({
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => await getLunchIntakeByDay(
    DayBoundaryCalc.currentLogicalDayLabel(
      dayStartOffsetHours,
      dayStartOffsetMinutes,
    ),
    dayStartOffsetHours: dayStartOffsetHours,
    dayStartOffsetMinutes: dayStartOffsetMinutes,
  );

  Future<List<IntakeEntity>> getDinnerIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => await _getIntakeByDay(
    IntakeTypeEntity.dinner,
    day,
    dayStartOffsetHours: dayStartOffsetHours,
    dayStartOffsetMinutes: dayStartOffsetMinutes,
  );

  Future<List<IntakeEntity>> getTodayDinnerIntake({
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => await getDinnerIntakeByDay(
    DayBoundaryCalc.currentLogicalDayLabel(
      dayStartOffsetHours,
      dayStartOffsetMinutes,
    ),
    dayStartOffsetHours: dayStartOffsetHours,
    dayStartOffsetMinutes: dayStartOffsetMinutes,
  );

  Future<List<IntakeEntity>> getSnackIntakeByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => await _getIntakeByDay(
    IntakeTypeEntity.snack,
    day,
    dayStartOffsetHours: dayStartOffsetHours,
    dayStartOffsetMinutes: dayStartOffsetMinutes,
  );

  Future<List<IntakeEntity>> getTodaySnackIntake({
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => await getSnackIntakeByDay(
    DayBoundaryCalc.currentLogicalDayLabel(
      dayStartOffsetHours,
      dayStartOffsetMinutes,
    ),
    dayStartOffsetHours: dayStartOffsetHours,
    dayStartOffsetMinutes: dayStartOffsetMinutes,
  );

  Future<List<IntakeEntity>> getRecentIntake() async {
    return _intakeRepository.getRecentIntake();
  }

  Future<IntakeEntity?> getIntakeById(String intakeId) async {
    return _intakeRepository.getIntakeById(intakeId);
  }

  Future<List<IntakeEntity>> getCustomMealIntakes() async {
    return _intakeRepository.getCustomMealIntakes();
  }
}
