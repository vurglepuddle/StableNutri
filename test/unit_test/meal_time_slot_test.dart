import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/utils/meal_time_slot.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';

void main() {
  test('food shortcut follows local meal-time boundaries', () {
    final expected = {
      0: AddMealType.snackType,
      4: AddMealType.snackType,
      5: AddMealType.breakfastType,
      10: AddMealType.breakfastType,
      11: AddMealType.lunchType,
      15: AddMealType.lunchType,
      16: AddMealType.dinnerType,
      21: AddMealType.dinnerType,
      22: AddMealType.snackType,
      23: AddMealType.snackType,
    };
    for (final entry in expected.entries) {
      expect(
        MealTimeSlot.at(
          DateTime(2026, 9, 22, entry.key),
          ConfigEntity.defaultMealKcalSharesPct,
        ),
        entry.value,
      );
    }
  });

  test('disabled meals are skipped, including OMAD', () {
    final shares = {ConfigEntity.mealKeyDinner: 100};
    for (var hour = 0; hour < 24; hour++) {
      expect(
        MealTimeSlot.at(DateTime(2026, 9, 22, hour), shares),
        AddMealType.dinnerType,
      );
    }
  });
}
