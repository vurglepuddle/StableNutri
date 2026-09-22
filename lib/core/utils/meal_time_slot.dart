import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';

/// Uses the device's local wall clock, including its current time zone.
/// The diary boundary controls the logged day, not breakfast's clock time.
abstract final class MealTimeSlot {
  static AddMealType at(DateTime localTime, Map<String, int> shares) {
    final hour = localTime.toLocal().hour;
    final preferred = hour >= 5 && hour < 11
        ? 0
        : hour >= 11 && hour < 16
        ? 1
        : hour >= 16 && hour < 22
        ? 2
        : 3;
    const keys = [
      ConfigEntity.mealKeyBreakfast,
      ConfigEntity.mealKeyLunch,
      ConfigEntity.mealKeyDinner,
      ConfigEntity.mealKeySnack,
    ];
    // Respect disabled meal slots (e.g. OMAD), taking the next enabled slot.
    for (var i = 0; i < keys.length; i++) {
      final index = (preferred + i) % keys.length;
      if ((shares[keys[index]] ?? 0) > 0) return AddMealType.values[index];
    }
    return AddMealType.values[preferred];
  }
}
