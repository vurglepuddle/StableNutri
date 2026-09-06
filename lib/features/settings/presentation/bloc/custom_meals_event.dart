part of 'custom_meals_bloc.dart';

abstract class CustomMealsEvent {}

class LoadCustomMealsEvent extends CustomMealsEvent {}

class DeleteCustomMealEvent extends CustomMealsEvent {
  final String mealKey;

  /// Whether to also remove the diary entries that used this meal.
  ///
  /// Defaults to **false**: deleting a saved meal is a Library action, and a
  /// diary entry is a record of something the user actually ate. [IntakeDBO]
  /// embeds its own [MealDBO] snapshot rather than pointing at the template,
  /// so history stays complete and readable once the template is gone —
  /// there is no orphan to clean up. Rewriting history is therefore a
  /// deliberate extra step the user opts into per deletion, not a side
  /// effect of tidying the Library.
  final bool deleteIntakes;

  DeleteCustomMealEvent(this.mealKey, {this.deleteIntakes = false});
}

class UpdateCustomMealLibraryFlagsEvent extends CustomMealsEvent {
  final MealEntity meal;
  final bool favorite;
  final bool rescue;

  UpdateCustomMealLibraryFlagsEvent({
    required this.meal,
    required this.favorite,
    required this.rescue,
  });
}

/// Folds [loserKey]'s diary entries into [winnerKey] and drops the loser
/// from the saved-meals list. Both keys are `meal.code ?? meal.name`.
class MergeCustomMealsEvent extends CustomMealsEvent {
  final String loserKey;
  final String winnerKey;

  MergeCustomMealsEvent({required this.loserKey, required this.winnerKey});
}
