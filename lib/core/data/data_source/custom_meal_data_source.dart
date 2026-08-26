import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

class CustomMealDataSource {
  final HiveDBProvider _db;

  CustomMealDataSource(this._db);

  Box<MealDBO> get _customMealBox => _db.customMealBox;

  Future<void> saveCustomMeal(MealDBO mealDBO) async {
    final existing = findMatchingMeal(MealEntity.fromMealDBO(mealDBO));
    if (existing != null) {
      // Editing or re-importing a saved item must not silently clear labels
      // that were set from the Library or food-detail screen.
      final merged = mealDBO.withLibraryFlags(
        favorite:
            (mealDBO.isFavorite ?? false) || (existing.isFavorite ?? false),
        rescue: (mealDBO.isRescue ?? false) || (existing.isRescue ?? false),
      );
      await _customMealBox.put(existing.key, merged);
    } else {
      await _customMealBox.add(mealDBO);
    }
  }

  List<MealDBO> getAllCustomMeals() => _customMealBox.values.toList();

  MealDBO? findMatchingMeal(MealEntity meal) {
    return _customMealBox.values.cast<MealDBO?>().firstWhere(
      (candidate) =>
          (meal.code != null && candidate?.code == meal.code) ||
          (meal.code == null && candidate?.name == meal.name),
      orElse: () => null,
    );
  }

  Future<MealEntity> setLibraryFlags(
    MealEntity meal, {
    required bool favorite,
    required bool rescue,
  }) async {
    final existing = findMatchingMeal(meal);
    final updated = meal.copyWith(isFavorite: favorite, isRescue: rescue);
    final dbo = MealDBO.fromMealEntity(updated);
    if (existing != null) {
      await _customMealBox.put(existing.key, dbo);
    } else {
      // Labelling a remote result also saves its full snapshot, so the item
      // remains available in the Library without a network connection.
      await _customMealBox.add(dbo);
    }
    return updated;
  }

  Future<void> addAllCustomMeals(List<MealDBO> meals) async {
    for (final meal in meals) {
      await saveCustomMeal(meal);
    }
  }

  Future<void> deleteCustomMeal(String mealKey) async {
    final toDelete = _customMealBox.values
        .where((m) => (m.code ?? m.name) == mealKey)
        .toList();
    for (final meal in toDelete) {
      await meal.delete();
    }
  }
}
