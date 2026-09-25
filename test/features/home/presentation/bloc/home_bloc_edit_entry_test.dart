import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_user_activity_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';

/// A 04:30 day boundary, so a 01:00 entry belongs to the day before.
class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => const ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.light,
    dayStartOffsetHours: 4,
    dayStartOffsetMinutes: 30,
  );
}

class _UpdateIntake extends Fake implements UpdateIntakeUsecase {
  final saved = <IntakeEntity>[];
  @override
  Future<void> putIntake(IntakeEntity intake) async => saved.add(intake);
}

/// Records every change to a day's tracked totals.
class _TrackedDay extends Fake implements AddTrackedDayUsecase {
  final changes = <String>[];

  @override
  Future<void> addDayCaloriesTracked(DateTime day, double kcal) async =>
      changes.add('${day.day} +kcal $kcal');

  @override
  Future<void> removeDayCaloriesTracked(DateTime day, double kcal) async =>
      changes.add('${day.day} -kcal $kcal');

  @override
  Future<void> addDayMacrosTracked(
    DateTime day, {
    double? carbsTracked,
    double? fatTracked,
    double? proteinTracked,
  }) async => changes.add(
    '${day.day} +c $carbsTracked f $fatTracked p $proteinTracked',
  );

  @override
  Future<void> removeDayMacrosTracked(
    DateTime day, {
    double? carbsTracked,
    double? fatTracked,
    double? proteinTracked,
  }) async => changes.add(
    '${day.day} -c $carbsTracked f $fatTracked p $proteinTracked',
  );
}

class _Diary extends Fake implements DiaryBloc {
  @override
  void add(DiaryEvent event) {}
}

class _CalendarDay extends Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}
}

MealEntity _food(double kcal, double carbs, double fat, double protein) =>
    MealEntity(
      code: 'food-$kcal',
      name: 'Food',
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: null,
      nutriments: MealNutrimentsEntity(
        energyKcal100: kcal,
        carbohydrates100: carbs,
        fat100: fat,
        proteins100: protein,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceEntity.custom,
    );

void main() {
  late HomeBloc bloc;
  late _UpdateIntake intakes;
  late _TrackedDay days;

  setUp(() {
    intakes = _UpdateIntake();
    days = _TrackedDay();
    locator.registerSingleton<DiaryBloc>(_Diary());
    locator.registerSingleton<CalendarDayBloc>(_CalendarDay());
    bloc = HomeBloc(
      _Config(),
      _AddConfigUsecase(),
      _GetIntakeUsecase(),
      _DeleteIntakeUsecase(),
      intakes,
      _GetUserActivityUsecase(),
      _DeleteUserActivityUsecase(),
      days,
      _GetKcalGoalUsecase(),
      _GetMacroGoalUsecase(),
      _UpdateUserActivityUsecase(),
      _GetUserUsecase(),
      _GetWaterIntakeUsecase(),
      _AddWaterIntakeUsecase(),
      _DeleteWaterIntakeUsecase(),
    );
  });

  tearDown(() async {
    await bloc.close();
    await locator.reset();
  });

  final old = IntakeEntity(
    id: 'entry',
    unit: 'g',
    amount: 100,
    type: IntakeTypeEntity.dinner,
    meal: _food(100, 10, 5, 2),
    dateTime: DateTime(2026, 9, 25, 1),
  );

  test('an edited entry moves its logical day by the difference', () async {
    final updated = IntakeEntity(
      id: 'entry',
      unit: 'g',
      amount: 200,
      type: IntakeTypeEntity.snack,
      meal: _food(50, 20, 1, 2),
      dateTime: old.dateTime,
    );
    await bloc.replaceIntakeItem(old, updated);

    expect(intakes.saved.single, same(updated));
    // Same energy; more carbs and protein, less fat. 01:00 on the 25th is
    // still the 24th with a 04:30 boundary.
    expect(days.changes, ['24 +c 30.0 f 0.0 p 2.0', '24 -c 0.0 f 3.0 p 0.0']);
  });

  test('undo puts the entry and its totals back', () async {
    await bloc.restoreIntakeItem(old);

    expect(intakes.saved.single, same(old));
    expect(days.changes, [
      '24 +kcal 100.0',
      '24 +c 10.0 f 5.0 p 2.0',
      '24 -c 0.0 f 0.0 p 0.0',
    ]);
  });
}

// Use cases the tested methods never touch.
class _AddConfigUsecase extends Fake implements AddConfigUsecase {}

class _AddWaterIntakeUsecase extends Fake implements AddWaterIntakeUsecase {}

class _DeleteIntakeUsecase extends Fake implements DeleteIntakeUsecase {}

class _DeleteUserActivityUsecase extends Fake
    implements DeleteUserActivityUsecase {}

class _DeleteWaterIntakeUsecase extends Fake
    implements DeleteWaterIntakeUsecase {}

class _GetIntakeUsecase extends Fake implements GetIntakeUsecase {}

class _GetKcalGoalUsecase extends Fake implements GetKcalGoalUsecase {}

class _GetMacroGoalUsecase extends Fake implements GetMacroGoalUsecase {}

class _GetUserActivityUsecase extends Fake implements GetUserActivityUsecase {}

class _GetUserUsecase extends Fake implements GetUserUsecase {}

class _GetWaterIntakeUsecase extends Fake implements GetWaterIntakeUsecase {}

class _UpdateUserActivityUsecase extends Fake
    implements UpdateUserActivityUsecase {}
