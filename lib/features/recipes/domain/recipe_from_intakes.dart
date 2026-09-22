import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_ingredient_entity.dart';
import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';

/// Builds an unsaved recipe from diary snapshots, without looking up current
/// Library foods or recipes (which may have changed since the meal was logged).
RecipeEntity recipeFromIntakes(
  List<IntakeEntity> intakes, {
  required String name,
}) {
  if (intakes.isEmpty) throw ArgumentError.value(intakes, 'intakes');
  final ingredients = intakes.map((intake) {
    final basis = intake.meal.mealUnit?.trim().toLowerCase() ?? '';
    if (!const {'', 'g', 'ml', 'g/ml', 'gml'}.contains(basis) ||
        !intake.amount.isFinite ||
        intake.amount <= 0) {
      throw const FormatException('A logged food has no usable gram/ml amount');
    }
    // Intake.amount already contains the base amount, even when intake.unit
    // records the chosen "serving" or "oz". Converting it again inflates totals.
    // Recipe calculations use the existing 1 ml = 1 g convention for liquids.
    return RecipeIngredientEntity(
      snapshotMeal: intake.meal,
      amount: intake.amount,
      unit: basis == 'ml' ? 'ml' : 'g',
      convertedAmountG: intake.amount,
    );
  }).toList();
  final result = ComputeRecipeNutritionUseCase().compute(ingredients);
  final now = DateTime.now();
  return RecipeEntity(
    id: '', // The builder's new-copy sentinel; initialization assigns a fresh ID.
    name: name,
    description: null,
    ingredients: ingredients,
    totalWeightG: result.totalWeightG,
    aggregatedNutrimentsPer100: result.perHundredG,
    createdAt: now,
    updatedAt: now,
    servingsCount: 1,
  );
}
