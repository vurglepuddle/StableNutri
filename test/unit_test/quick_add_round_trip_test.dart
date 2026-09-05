import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

// Issue #451 — Quick Add. The form stores values per 100 g on the
// nutriments entity, with the intake carrying amount=100 g, so the totals
// math in IntakeEntity returns the exact numbers the user typed. This
// test pins that invariant so a future refactor of the nutriments model
// can't silently break the Quick Add flow.

IntakeEntity _buildIntake({
  required double kcal,
  double? carbs,
  double? fat,
  double? protein,
}) {
  final nutriments = MealNutrimentsEntity(
    energyKcal100: kcal,
    carbohydrates100: carbs,
    fat100: fat,
    proteins100: protein,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  );
  final meal = MealEntity(
    code: 'quick-add-test',
    name: 'Quick add',
    url: null,
    mealQuantity: '100',
    mealUnit: 'gml',
    servingQuantity: null,
    servingUnit: 'gml',
    servingSize: '',
    nutriments: nutriments,
    source: MealSourceEntity.custom,
  );
  return IntakeEntity(
    id: 'intake-test',
    unit: 'g',
    amount: 100,
    type: IntakeTypeEntity.breakfast,
    meal: meal,
    dateTime: DateTime(2026, 5, 23),
  );
}

void main() {
  group('Quick Add — entered values round-trip through IntakeEntity', () {
    test('500 kcal entered returns 500 kcal total', () {
      final intake = _buildIntake(kcal: 500);
      expect(intake.totalKcal, closeTo(500, 0.0001));
    });

    test('macros round-trip exactly when entered alongside kcal', () {
      final intake = _buildIntake(kcal: 420, carbs: 30, fat: 12, protein: 25);
      expect(intake.totalKcal, closeTo(420, 0.0001));
      expect(intake.totalCarbsGram, closeTo(30, 0.0001));
      expect(intake.totalFatsGram, closeTo(12, 0.0001));
      expect(intake.totalProteinsGram, closeTo(25, 0.0001));
    });

    test('omitted macros stay at zero in totals', () {
      final intake = _buildIntake(kcal: 100);
      expect(intake.totalCarbsGram, 0);
      expect(intake.totalFatsGram, 0);
      expect(intake.totalProteinsGram, 0);
    });
  });
}
