import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

/// Applies the two user-controlled Stable Library labels while keeping the
/// existing custom-meal and recipe stores as the source of truth.
class UpdateLibraryItemUsecase {
  final CustomMealDataSource _customMealDataSource;
  final RecipeDataSource _recipeDataSource;

  UpdateLibraryItemUsecase(this._customMealDataSource, this._recipeDataSource);

  MealEntity? getSavedMeal(MealEntity meal) {
    final dbo = _customMealDataSource.findMatchingMeal(meal);
    return dbo == null ? null : MealEntity.fromMealDBO(dbo);
  }

  Future<MealEntity> updateMeal(
    MealEntity meal, {
    required bool favorite,
    required bool rescue,
  }) => _customMealDataSource.setLibraryFlags(
    meal,
    favorite: favorite,
    rescue: rescue,
  );

  Future<RecipeEntity?> updateRecipe(
    String id, {
    required bool favorite,
    required bool rescue,
  }) async {
    final dbo = await _recipeDataSource.setLibraryFlags(
      id,
      favorite: favorite,
      rescue: rescue,
    );
    return dbo == null ? null : RecipeEntity.fromDBO(dbo);
  }
}
