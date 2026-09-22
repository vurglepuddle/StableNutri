import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/domain/recipe_from_intakes.dart';

IntakeEntity intake({
  String? basis = 'g',
  String selected = 'g',
  double amount = 100,
  double kcal = 200,
  MealSourceEntity source = MealSourceEntity.custom,
}) => IntakeEntity(
  id: 'logged',
  unit: selected,
  amount: amount,
  type: IntakeTypeEntity.dinner,
  dateTime: DateTime(2025, 1, 1),
  meal: MealEntity(
    code: 'food',
    name: 'Food',
    url: null,
    mealQuantity: null,
    mealUnit: basis,
    servingQuantity: 25,
    servingUnit: 'g',
    servingSize: '25 g',
    source: source,
    nutriments: MealNutrimentsEntity(
      energyKcal100: kcal,
      carbohydrates100: 20,
      fat100: 10,
      proteins100: 5,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
      sodium100: 123,
    ),
  ),
);

void main() {
  test('copies all snapshots and preserves combined nutrition and micros', () {
    final foods = [
      intake(amount: 150),
      intake(basis: 'ml', amount: 200, kcal: 50),
    ];
    final draft = recipeFromIntakes(foods, name: 'Dinner');
    expect(draft.id, isEmpty);
    expect(draft.name, 'Dinner');
    expect(draft.servingsCount, 1);
    expect(draft.ingredients, hasLength(2));
    expect(draft.ingredients.last.unit, 'ml');
    expect(draft.totalWeightG, 350);
    expect(
      draft.aggregatedNutrimentsPer100.energyKcal100! * 3.5,
      closeTo(400, 1e-9),
    );
    expect(draft.aggregatedNutrimentsPer100.sodium100, closeTo(123, 1e-9));
    expect(draft.aggregatedNutrimentsPer100.fiber100, isNull);
    draft.ingredients.removeLast();
    expect(foods, hasLength(2));
    expect(foods.first.amount, 150);
  });

  for (final selected in ['serving', 'oz', 'fl.oz']) {
    test(
      'does not convert the already-normalized $selected quantity twice',
      () {
        final food = intake(selected: selected, amount: 50);
        final draft = recipeFromIntakes([food], name: 'Meal');
        expect(draft.ingredients.single.amount, 50);
        expect(draft.totalWeightG, 50);
        expect(
          draft.aggregatedNutrimentsPer100.energyKcal100! * .5,
          food.totalKcal,
        );
      },
    );
  }

  test('logged recipes remain snapshots without a live recipe lookup', () {
    final food = intake(source: MealSourceEntity.recipe);
    final draft = recipeFromIntakes([food], name: 'New combination');
    expect(
      draft.ingredients.single.snapshotMeal.nutriments,
      food.meal.nutriments,
    );
    expect(draft.id, isNot(food.meal.code));
  });

  test('zero-calorie food is retained', () {
    expect(
      recipeFromIntakes([intake(kcal: 0)], name: 'Meal').ingredients,
      hasLength(1),
    );
  });

  test(
    'does not invent weights for source-serving imports or invalid amounts',
    () {
      for (final food in [
        intake(basis: 'serving'),
        intake(amount: 0),
        intake(amount: double.nan),
      ]) {
        expect(
          () => recipeFromIntakes([intake(), food], name: 'Meal'),
          throwsFormatException,
        );
      }
      expect(() => recipeFromIntakes([], name: 'Meal'), throwsArgumentError);
    },
  );
}
