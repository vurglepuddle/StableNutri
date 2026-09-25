import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';

/// The food form saves what it shows: one serving of so many grams or
/// millilitres, and nutrition per 100 of them. Its old Simple mode stored a
/// serving's totals as per-100 values, so every new food logged "1 serving"
/// as 100 g.
///
/// The fakes are unused stand-ins — `createNewMealEntity` is a pure transform
/// over its arguments and touches none of the bloc's dependencies.
class _FakeGetConfigUsecase implements GetConfigUsecase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCustomMealDataSource implements CustomMealDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const FoodNutritionPer100 _tomato = (
  kcal: 18,
  carbs: 4,
  fat: 0.2,
  protein: 1,
  fiber: 1.2,
  saturatedFat: null,
  sugars: 2.6,
  sodium: null,
  calcium: null,
  iron: null,
  potassium: null,
  magnesium: null,
  vitaminD: null,
  vitaminB12: null,
);

void main() {
  late EditMealBloc bloc;

  setUp(() {
    bloc = EditMealBloc(_FakeGetConfigUsecase(), _FakeCustomMealDataSource());
  });

  tearDown(() async {
    await bloc.close();
  });

  MealEntity build(
    MealEntity old, {
    String? unit = 'g',
    double? servingQuantity = 150,
  }) => bloc.createNewMealEntity(
    old,
    name: ' Tomato ',
    brands: '',
    unit: unit,
    servingQuantity: servingQuantity,
    per100: _tomato,
  );

  test('a new food keeps its serving and per-100 values apart', () {
    final meal = build(MealEntity.empty());
    expect(meal.name, 'Tomato');
    expect(meal.brands, isNull);
    expect(meal.mealUnit, 'g');
    expect(meal.servingQuantity, 150);
    // #495: the serving's unit is the selected unit, not the quantity text.
    expect(meal.servingUnit, 'g');
    expect(meal.scalableServingQuantity, 150);
    expect(meal.nutriments.energyKcal100, 18);
    expect(meal.nutriments.sugars100, 2.6);
    expect(meal.mealQuantity, isNull);
    expect(meal.detailed, isTrue);
  });

  test('a liquid is measured in millilitres, serving and all', () {
    final meal = build(MealEntity.empty(), unit: 'ml', servingQuantity: 250);
    expect(meal.mealUnit, 'ml');
    expect(meal.servingUnit, 'ml');
    expect(meal.isLiquid, isTrue);
  });

  test('no serving size means no serving to pick', () {
    final meal = build(MealEntity.empty(), servingQuantity: null);
    expect(meal.scalableServingQuantity, isNull);
  });

  MealEntity product({String? servingSize = '1 slice (25 g)'}) => MealEntity(
    code: '4000000000000',
    name: 'Bread',
    url: null,
    mealQuantity: '500',
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: null,
    servingSize: servingSize,
    nutriments: const MealNutrimentsEntity(
      energyKcal100: 250,
      carbohydrates100: 45,
      fat100: 3,
      proteins100: 9,
      sugars100: 3,
      saturatedFat100: 0.5,
      fiber100: 6,
      zinc100: 1.1,
      vitaminC100: 0.4,
    ),
    source: MealSourceEntity.off,
    isFavorite: true,
  );

  test('an unchanged serving keeps its description', () {
    final meal = build(product(), servingQuantity: 25);
    expect(meal.servingSize, '1 slice (25 g)');
  });

  test('a changed serving drops the description that no longer fits', () {
    final meal = build(product(), servingQuantity: 40);
    expect(meal.servingSize, isNull);
    expect(meal.scalableServingQuantity, 40);
  });

  test('nutrients the form does not show are kept, and so are labels', () {
    final meal = build(product(), servingQuantity: 25);
    expect(meal.nutriments.zinc100, 1.1);
    expect(meal.nutriments.vitaminC100, 0.4);
    expect(meal.mealQuantity, '500');
    expect(meal.isFavorite, isTrue);
    expect(meal.code, '4000000000000');
  });

  test('a food counted in servings keeps its units', () {
    final lifesum = MealEntity(
      code: 'lifesum-meal-1',
      name: 'Pizza slice',
      url: null,
      mealQuantity: null,
      mealUnit: 'serving',
      servingQuantity: 1,
      servingUnit: 'serving',
      servingSize: 'slice',
      nutriments: MealNutrimentsEntity.empty(),
      source: MealSourceEntity.custom,
    );
    final meal = build(lifesum, unit: null, servingQuantity: null);
    expect(meal.mealUnit, 'serving');
    expect(meal.servingUnit, 'serving');
    expect(meal.servingQuantity, 1);
    expect(meal.servingSize, 'slice');
  });

  test('weights and volumes show as g or ml; servings do not', () {
    for (final unit in [null, '', 'g', 'ml', 'g/ml', 'gml', 'oz', 'kg']) {
      expect(isMeasuredByWeightOrVolume(unit), isTrue, reason: '$unit');
    }
    expect(isMeasuredByWeightOrVolume('serving'), isFalse);
  });
}
