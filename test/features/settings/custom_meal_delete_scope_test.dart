import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/merge_custom_meals_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/custom_meals_bloc.dart';

/// Deleting a saved meal is a Library action. A diary entry is a record of
/// something the user actually ate, and [IntakeDBO] embeds its own meal
/// snapshot rather than pointing at the template — so history survives the
/// template's deletion intact, and rewriting it has to be asked for.
void main() {
  late _FakeCustomMealDataSource meals;
  late _FakeGetIntakeUsecase intakes;
  late _RecordingDeleteIntakeUsecase deletions;
  late _RecordingAddTrackedDayUsecase trackedDays;

  CustomMealsBloc buildBloc() => CustomMealsBloc(
    meals,
    intakes,
    deletions,
    trackedDays,
    _UnusedMergeUseCase(),
  );

  setUp(() {
    meals = _FakeCustomMealDataSource();
    intakes = _FakeGetIntakeUsecase();
    deletions = _RecordingDeleteIntakeUsecase();
    trackedDays = _RecordingAddTrackedDayUsecase();

    intakes.entries.addAll([
      _intake(id: 'a', mealKey: '5995327152479'),
      _intake(id: 'b', mealKey: '5995327152479'),
      _intake(id: 'c', mealKey: 'something-else'),
    ]);
  });

  test(
    'deleting by default drops the template and keeps every entry',
    () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);

      bloc.add(DeleteCustomMealEvent('5995327152479'));
      await Future<void>.delayed(Duration.zero);

      expect(meals.deletedKeys, ['5995327152479']);
      expect(
        deletions.deleted,
        isEmpty,
        reason: 'a Library tidy-up must not rewrite the diary',
      );
      expect(trackedDays.caloriesRemoved, isEmpty);
      expect(trackedDays.macrosRemoved, isEmpty);
    },
  );

  test('deleteIntakes: true removes the matching entries and unwinds their '
      'tracked-day totals', () async {
    final bloc = buildBloc();
    addTearDown(bloc.close);

    bloc.add(DeleteCustomMealEvent('5995327152479', deleteIntakes: true));
    await Future<void>.delayed(Duration.zero);

    expect(meals.deletedKeys, ['5995327152479']);
    expect(deletions.deleted.map((i) => i.id), ['a', 'b']);
    expect(
      trackedDays.caloriesRemoved,
      hasLength(2),
      reason: 'each removed entry has to give its calories back',
    );
    expect(trackedDays.macrosRemoved, hasLength(2));
  });

  test(
    'an unrelated meal keeps its entries even on an opted-in delete',
    () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);

      bloc.add(DeleteCustomMealEvent('5995327152479', deleteIntakes: true));
      await Future<void>.delayed(Duration.zero);

      expect(deletions.deleted.map((i) => i.id), isNot(contains('c')));
    },
  );

  group('countLoggedEntries', () {
    test('counts exactly what an opted-in delete would remove', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);

      expect(await bloc.countLoggedEntries('5995327152479'), 2);
      expect(await bloc.countLoggedEntries('something-else'), 1);
      expect(await bloc.countLoggedEntries('never-logged'), 0);
    });

    test(
      'the count matches the delete, so the dialog cannot overpromise',
      () async {
        final bloc = buildBloc();
        addTearDown(bloc.close);

        final predicted = await bloc.countLoggedEntries('5995327152479');
        bloc.add(DeleteCustomMealEvent('5995327152479', deleteIntakes: true));
        await Future<void>.delayed(Duration.zero);

        expect(deletions.deleted, hasLength(predicted));
      },
    );
  });
}

IntakeEntity _intake({required String id, required String mealKey}) =>
    IntakeEntity(
      id: id,
      unit: 'g',
      amount: 100,
      type: IntakeTypeEntity.breakfast,
      dateTime: DateTime(2026, 9, 6),
      meal: MealEntity(
        code: mealKey,
        name: 'Test food',
        url: null,
        mealQuantity: '100',
        mealUnit: 'g',
        servingQuantity: null,
        servingUnit: 'g',
        servingSize: null,
        source: MealSourceEntity.custom,
        nutriments: const MealNutrimentsEntity(
          energyKcal100: 100,
          carbohydrates100: 4,
          fat100: 5,
          proteins100: 10,
          sugars100: null,
          saturatedFat100: null,
          fiber100: null,
        ),
      ),
    );

class _FakeCustomMealDataSource implements CustomMealDataSource {
  final List<String> deletedKeys = [];

  @override
  Future<void> deleteCustomMeal(String mealKey) async =>
      deletedKeys.add(mealKey);

  @override
  List<MealDBO> getAllCustomMeals() => [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeGetIntakeUsecase implements GetIntakeUsecase {
  final List<IntakeEntity> entries = [];

  @override
  Future<List<IntakeEntity>> getCustomMealIntakes() async => entries;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _RecordingDeleteIntakeUsecase implements DeleteIntakeUsecase {
  final List<IntakeEntity> deleted = [];

  @override
  Future<void> deleteIntake(IntakeEntity intakeEntity) async =>
      deleted.add(intakeEntity);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _RecordingAddTrackedDayUsecase implements AddTrackedDayUsecase {
  final List<double> caloriesRemoved = [];
  final List<DateTime> macrosRemoved = [];

  @override
  Future<void> removeDayCaloriesTracked(DateTime day, double calories) async =>
      caloriesRemoved.add(calories);

  @override
  Future<void> removeDayMacrosTracked(
    DateTime day, {
    double? carbsTracked,
    double? fatTracked,
    double? proteinTracked,
  }) async => macrosRemoved.add(day);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

/// The merge path is not under test here; any call is a bug in the test.
class _UnusedMergeUseCase implements MergeCustomMealsUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}
