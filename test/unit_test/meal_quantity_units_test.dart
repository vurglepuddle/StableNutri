import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_quantity_units.dart';

MealEntity meal({String? unit, double? serving, String? servingSize}) =>
    MealEntity(
      code: 'test',
      name: 'Test',
      url: null,
      mealQuantity: null,
      mealUnit: unit,
      servingQuantity: serving,
      servingUnit: unit,
      servingSize: servingSize,
      nutriments: MealNutrimentsEntity.empty(),
      source: MealSourceEntity.off,
    );

void main() {
  test('external unit casing and whitespace preserve product classification', () {
    expect(MealQuantityUnits(meal(unit: ' ML ')).defaultUnit(), 'ml');
    expect(MealQuantityUnits(meal(unit: ' G ')).defaultUnit(), 'g');
  });
  test('every default has exactly one item across all product shapes', () {
    for (final unit in [
      null,
      '',
      'g',
      'ml',
      'g/ml',
      'kg',
      'l',
      'serving',
      'invalid',
    ]) {
      for (final serving in [
        null,
        0.0,
        -1.0,
        30.0,
        double.nan,
        double.infinity,
      ]) {
        for (final recipe in [false, true]) {
          final options = MealQuantityUnits(
            meal(unit: unit, serving: serving),
            forRecipe: recipe,
          );
          expect(options.values.toSet().length, options.values.length);
          for (final imperial in [false, true]) {
            expect(
              options.values.where(
                (v) => v == options.defaultUnit(imperial: imperial),
              ),
              hasLength(1),
            );
          }
          for (final selected in [
            'g',
            'ml',
            'kg',
            'mg',
            'l',
            'cl',
            'dl',
            'oz',
            'fl oz',
            ' FL.OZ ',
            'serving',
            'missing',
            '',
          ]) {
            final resolved = options.reconcile(selected, '2');
            expect(
              options.values.where((v) => v == resolved.unit),
              hasLength(1),
            );
          }
        }
      }
    }
  });

  test('hydration reconciles g on a liquid and preserves base quantity', () {
    final result = MealQuantityUnits(
      meal(unit: 'ml'),
    ).reconcile('g', '125', previousMeal: meal());
    expect(result.unit, 'ml');
    expect(double.parse(result.amount), 125);
  });

  test('removed serving converts using the previous product snapshot', () {
    final result = MealQuantityUnits(
      meal(unit: 'g'),
    ).reconcile('serving', '2', previousMeal: meal(serving: 30));
    expect(result.unit, 'g');
    expect(double.parse(result.amount), 60);
  });

  test('legacy recipe units convert rather than changing their meaning', () {
    final result = MealQuantityUnits(
      meal(unit: 'ml'),
      forRecipe: true,
    ).reconcile('cl', '25');
    expect(result.unit, 'ml');
    expect(double.parse(result.amount), 250);
    final stale = MealQuantityUnits(
      meal(),
      forRecipe: true,
    ).reconcile('serving', '2');
    expect(stale.unit, 'g');
    expect(stale.amount, isEmpty);
  });

  test(
    'invalid serving weights are unavailable; valid text can recover them',
    () {
      expect(meal(serving: 0).scalableServingQuantity, isNull);
      expect(meal(serving: double.infinity).scalableServingQuantity, isNull);
      expect(meal(servingSize: '0 g').scalableServingQuantity, isNull);
      expect(
        meal(serving: 0, servingSize: '1 slice (30 g)').scalableServingQuantity,
        30,
      );
    },
  );
}
