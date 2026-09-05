import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

MealEntity _meal({
  String code = '1',
  required MealNutrimentsEntity nutriments,
  double? servingQuantity,
}) {
  return MealEntity(
    code: code,
    name: 'test',
    url: null,
    mealQuantity: null,
    mealUnit: 'g',
    servingQuantity: servingQuantity,
    servingUnit: servingQuantity != null ? 'g' : null,
    servingSize: null,
    nutriments: nutriments,
    source: MealSourceEntity.custom,
  );
}

MealNutrimentsEntity _nutr({
  double? kcal,
  double? carbs,
  double? fat,
  double? protein,
  double? sugar,
  double? satFat,
  double? fiber,
  double? sodium,
  double? iron,
}) {
  return MealNutrimentsEntity(
    energyKcal100: kcal,
    carbohydrates100: carbs,
    fat100: fat,
    proteins100: protein,
    sugars100: sugar,
    saturatedFat100: satFat,
    fiber100: fiber,
    sodium100: sodium,
    iron100: iron,
  );
}

RecipeIngredientEntity _ingredient(
  MealEntity meal,
  double amount,
  String unit,
  double convertedG,
) {
  return RecipeIngredientEntity(
    snapshotMeal: meal,
    amount: amount,
    unit: unit,
    convertedAmountG: convertedG,
  );
}

void main() {
  late ComputeRecipeNutritionUseCase useCase;

  setUp(() {
    useCase = ComputeRecipeNutritionUseCase();
  });

  group('convertAmountToGrams', () {
    test('grams pass through', () {
      expect(useCase.convertAmountToGrams(amount: 150, unit: 'g'), 150);
    });

    test('ml treated 1:1 as grams', () {
      expect(useCase.convertAmountToGrams(amount: 250, unit: 'ml'), 250);
    });

    test('kg multiplied by 1000', () {
      expect(useCase.convertAmountToGrams(amount: 1.5, unit: 'kg'), 1500);
    });

    test('mg divided by 1000', () {
      expect(useCase.convertAmountToGrams(amount: 500, unit: 'mg'), 0.5);
    });

    test('oz converted via UnitCalc', () {
      // 1 oz ≈ 28.3495 g
      expect(
        useCase.convertAmountToGrams(amount: 1, unit: 'oz'),
        closeTo(28.35, 0.01),
      );
    });

    test('fl.oz converted via UnitCalc', () {
      // 1 fl.oz ≈ 29.5735 ml ≈ 29.5735 g
      expect(
        useCase.convertAmountToGrams(amount: 1, unit: 'fl.oz'),
        closeTo(29.57, 0.01),
      );
    });

    test('serving uses snapshot servingQuantity', () {
      expect(
        useCase.convertAmountToGrams(
          amount: 2,
          unit: 'serving',
          servingQuantityG: 30,
        ),
        60,
      );
    });

    test('serving without servingQuantity returns null', () {
      expect(useCase.convertAmountToGrams(amount: 2, unit: 'serving'), isNull);
    });

    test('unknown unit returns null', () {
      expect(
        useCase.convertAmountToGrams(amount: 1, unit: 'tablespoon'),
        isNull,
      );
    });
  });

  group('compute', () {
    test('empty ingredient list returns empty + zero weight', () {
      final result = useCase.compute([]);

      expect(result.totalWeightG, 0);
      expect(result.perHundredG.energyKcal100, isNull);
      expect(result.perHundredG.carbohydrates100, isNull);
    });

    test('single ingredient passes through unchanged at per-100g', () {
      // 100 g of a 200 kcal/100g food → recipe per-100g = 200 kcal
      final flour = _meal(nutriments: _nutr(kcal: 200, carbs: 70, protein: 10));
      final result = useCase.compute([_ingredient(flour, 100, 'g', 100)]);

      expect(result.totalWeightG, 100);
      expect(result.perHundredG.energyKcal100, closeTo(200, 0.001));
      expect(result.perHundredG.carbohydrates100, closeTo(70, 0.001));
      expect(result.perHundredG.proteins100, closeTo(10, 0.001));
    });

    test('two solid ingredients aggregate correctly', () {
      // 50 g flour @ 340 kcal/100g + 50 g sugar @ 390 kcal/100g
      // total kcal: 170 + 195 = 365 over 100 g → per-100g = 365
      final flour = _meal(code: 'flour', nutriments: _nutr(kcal: 340));
      final sugar = _meal(code: 'sugar', nutriments: _nutr(kcal: 390));
      final result = useCase.compute([
        _ingredient(flour, 50, 'g', 50),
        _ingredient(sugar, 50, 'g', 50),
      ]);

      expect(result.totalWeightG, 100);
      expect(result.perHundredG.energyKcal100, closeTo(365, 0.001));
    });

    test('mixed g + ml (1:1) aggregates correctly', () {
      // 100 g flour @ 340 + 100 ml milk @ 60 (treated as 100 g)
      // total kcal: 340 + 60 = 400 over 200 g → per-100g = 200
      final flour = _meal(code: 'flour', nutriments: _nutr(kcal: 340));
      final milk = _meal(code: 'milk', nutriments: _nutr(kcal: 60));
      final result = useCase.compute([
        _ingredient(flour, 100, 'g', 100),
        _ingredient(milk, 100, 'ml', 100),
      ]);

      expect(result.totalWeightG, 200);
      expect(result.perHundredG.energyKcal100, closeTo(200, 0.001));
    });

    test('totalWeightOverride rescales per-100g', () {
      // 800 g of dough at 200 kcal/100g (1600 kcal total) baked down to 720 g
      // → per-100g = 1600 × 100 / 720 ≈ 222.22
      final dough = _meal(nutriments: _nutr(kcal: 200));
      final result = useCase.compute([
        _ingredient(dough, 800, 'g', 800),
      ], totalWeightOverride: 720);

      expect(result.totalWeightG, 720);
      expect(result.perHundredG.energyKcal100, closeTo(222.22, 0.01));
    });

    test(
      'null nutrient field treated as 0 in sum, but null preserved when ALL ingredients null',
      () {
        // ingredient A has iron, B has null iron
        // → recipe iron = (5 mg × 50 g + 0 × 50 g) × 100 / 100 = 2.5 mg
        final a = _meal(code: 'a', nutriments: _nutr(kcal: 100, iron: 5));
        final b = _meal(code: 'b', nutriments: _nutr(kcal: 100));
        final result = useCase.compute([
          _ingredient(a, 50, 'g', 50),
          _ingredient(b, 50, 'g', 50),
        ]);

        expect(result.perHundredG.iron100, closeTo(2.5, 0.001));
      },
    );

    test('all ingredients null for a field → recipe field also null', () {
      final a = _meal(code: 'a', nutriments: _nutr(kcal: 100));
      final b = _meal(code: 'b', nutriments: _nutr(kcal: 100));
      final result = useCase.compute([
        _ingredient(a, 50, 'g', 50),
        _ingredient(b, 50, 'g', 50),
      ]);

      // None of the ingredients had iron data → recipe iron is null too,
      // not 0 (preserves "hide unknown micros" UI behaviour).
      expect(result.perHundredG.iron100, isNull);
      expect(result.perHundredG.vitaminA100, isNull);
    });

    test('zero total weight yields empty nutriments', () {
      final a = _meal(nutriments: _nutr(kcal: 100));
      final result = useCase.compute([
        _ingredient(a, 50, 'g', 50),
      ], totalWeightOverride: 0);

      expect(result.totalWeightG, 0);
      expect(result.perHundredG.energyKcal100, isNull);
    });

    test(
      'full-nutrient coverage: every MealNutrimentsEntity field aggregates',
      () {
        // Three ingredients each populating all 24 fields with the same value v.
        // The weighted-mean of identical values is the same value back —
        // ensures every field is summed (not just kcal/carbs/fat/protein).
        const v = 10.0;
        final fullN = MealNutrimentsEntity(
          energyKcal100: v,
          carbohydrates100: v,
          fat100: v,
          proteins100: v,
          sugars100: v,
          saturatedFat100: v,
          fiber100: v,
          monounsaturatedFat100: v,
          polyunsaturatedFat100: v,
          transFat100: v,
          cholesterol100: v,
          sodium100: v,
          potassium100: v,
          magnesium100: v,
          calcium100: v,
          iron100: v,
          zinc100: v,
          phosphorus100: v,
          vitaminA100: v,
          vitaminC100: v,
          vitaminD100: v,
          vitaminB6100: v,
          vitaminB12100: v,
          niacin100: v,
        );
        final m1 = _meal(code: 'a', nutriments: fullN);
        final m2 = _meal(code: 'b', nutriments: fullN);
        final m3 = _meal(code: 'c', nutriments: fullN);
        final result = useCase.compute([
          _ingredient(m1, 100, 'g', 100),
          _ingredient(m2, 50, 'g', 50),
          _ingredient(m3, 50, 'g', 50),
        ]);

        final p = result.perHundredG;
        // Every field must equal v (weighted mean of identical values).
        expect(p.energyKcal100, closeTo(v, 0.001));
        expect(p.carbohydrates100, closeTo(v, 0.001));
        expect(p.fat100, closeTo(v, 0.001));
        expect(p.proteins100, closeTo(v, 0.001));
        expect(p.sugars100, closeTo(v, 0.001));
        expect(p.saturatedFat100, closeTo(v, 0.001));
        expect(p.fiber100, closeTo(v, 0.001));
        expect(p.monounsaturatedFat100, closeTo(v, 0.001));
        expect(p.polyunsaturatedFat100, closeTo(v, 0.001));
        expect(p.transFat100, closeTo(v, 0.001));
        expect(p.cholesterol100, closeTo(v, 0.001));
        expect(p.sodium100, closeTo(v, 0.001));
        expect(p.potassium100, closeTo(v, 0.001));
        expect(p.magnesium100, closeTo(v, 0.001));
        expect(p.calcium100, closeTo(v, 0.001));
        expect(p.iron100, closeTo(v, 0.001));
        expect(p.zinc100, closeTo(v, 0.001));
        expect(p.phosphorus100, closeTo(v, 0.001));
        expect(p.vitaminA100, closeTo(v, 0.001));
        expect(p.vitaminC100, closeTo(v, 0.001));
        expect(p.vitaminD100, closeTo(v, 0.001));
        expect(p.vitaminB6100, closeTo(v, 0.001));
        expect(p.vitaminB12100, closeTo(v, 0.001));
        expect(p.niacin100, closeTo(v, 0.001));
      },
    );
  });
}
