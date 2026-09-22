import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

/// One source for selectable unit IDs and selection reconciliation. Labels
/// never serve as IDs, and external/saved units are canonicalized on entry.
class MealQuantityUnits {
  MealQuantityUnits(this.meal, {this.forRecipe = false});

  final MealEntity meal;
  final bool forRecipe;

  static String canonical(String? unit) {
    final value = unit?.trim().toLowerCase() ?? '';
    return value == 'fl oz' ? 'fl.oz' : value;
  }

  List<String> get values => [
    if (meal.scalableServingQuantity != null) 'serving',
    if (!meal.isLiquid) ...['g', if (forRecipe) 'kg', 'oz'],
    if (!meal.isSolid) ...['ml', if (forRecipe) 'l', 'fl.oz'],
    if (!forRecipe) 'g/ml',
  ];

  String get baseUnit => meal.isLiquid ? 'ml' : 'g';

  String defaultUnit({bool imperial = false}) {
    if (meal.scalableServingQuantity != null) return 'serving';
    if (meal.isLiquid) return imperial ? 'fl.oz' : 'ml';
    if (meal.isSolid || forRecipe) return imperial ? 'oz' : 'g';
    return 'g/ml';
  }

  /// Preserve a valid selection. If metadata removed the selected unit,
  /// convert its amount to the new base unit using the previous snapshot.
  /// An unconvertible saved unit requires a new amount, never a guessed one.
  ({String unit, String amount}) reconcile(
    String? unit,
    String amount, {
    MealEntity? previousMeal,
  }) {
    final normalized = canonical(unit);
    if (values.contains(normalized)) return (unit: normalized, amount: amount);
    final quantity = double.tryParse(amount.replaceAll(',', '.'));
    final converted = quantity == null
        ? null
        : ComputeRecipeNutritionUseCase().convertAmountToGrams(
            amount: quantity,
            unit: normalized,
            servingQuantityG: (previousMeal ?? meal).scalableServingQuantity,
          );
    return (
      unit: baseUnit,
      amount: converted != null && converted.isFinite
          ? converted.toString()
          : '',
    );
  }
}
