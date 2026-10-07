import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

/// Uses the same nutrients, units and visibility keys as the diary panel.
enum WeeklyNutrient {
  fiber('fiber', 'g'),
  sodium('sodium', 'mg'),
  saturatedFat('saturated_fat', 'g'),
  sugar('sugar', 'g'),
  calcium('calcium', 'mg'),
  iron('iron', 'mg'),
  potassium('potassium', 'mg'),
  vitaminD('vitamin_d', '\u00b5g'),
  vitaminB12('vitamin_b12', '\u00b5g'),
  magnesium('magnesium', 'mg');

  final String key;
  final String unit;
  const WeeklyNutrient(this.key, this.unit);
  double? read(MealNutrimentsEntity n) => switch (this) {
    fiber => n.fiber100,
    sodium => n.sodium100,
    saturatedFat => n.saturatedFat100,
    sugar => n.sugars100,
    calcium => n.calcium100,
    iron => n.iron100,
    potassium => n.potassium100,
    vitaminD => n.vitaminD100,
    vitaminB12 => n.vitaminB12100,
    magnesium => n.magnesium100,
  };
}

class NutrientAggregate {
  final double? total;
  final int missingFoods;
  final int loggedDays;
  const NutrientAggregate(this.total, this.missingFoods, this.loggedDays);
  // An average is withheld if any logged food lacks this nutrient. Zero is
  // a known value; an empty diary day is not a zero-intake day.
  double? get dailyAverage => missingFoods > 0 || loggedDays == 0
      ? null
      : total == null
      ? null
      : total! / loggedDays;
}

class WeeklyNutrients {
  final DateTime start;
  final DateTime end;
  final int loggedDays;
  final Map<WeeklyNutrient, NutrientAggregate> nutrients;
  const WeeklyNutrients(this.start, this.end, this.loggedDays, this.nutrients);

  factory WeeklyNutrients.calculate(
    Iterable<IntakeEntity> intakes, {
    required DateTime endDay,
    int offsetMinutes = 0,
  }) {
    final end = DateTime(endDay.year, endDay.month, endDay.day);
    final start = DateTime(end.year, end.month, end.day - 6);
    final days = <DateTime>{};
    final totals = <WeeklyNutrient, double>{};
    final missing = <WeeklyNutrient, int>{};
    for (final intake in intakes) {
      final day = DayBoundaryCalc.logicalDayOfEntry(
        intake.dateTime,
        offsetMinutes,
      );
      if (day.isBefore(start) || day.isAfter(end) || intake.amount <= 0)
        continue;
      days.add(day);
      for (final nutrient in WeeklyNutrient.values) {
        final value = nutrient.read(intake.meal.nutriments);
        if (value == null || !value.isFinite || !intake.amount.isFinite) {
          missing[nutrient] = (missing[nutrient] ?? 0) + 1;
        } else {
          totals[nutrient] =
              (totals[nutrient] ?? 0) + value * intake.amount / 100;
        }
      }
    }
    return WeeklyNutrients(start, end, days.length, {
      for (final nutrient in WeeklyNutrient.values)
        nutrient: NutrientAggregate(
          totals[nutrient],
          missing[nutrient] ?? 0,
          days.length,
        ),
    });
  }
}
