part of 'recipes_bloc.dart';

sealed class RecipesEvent extends Equatable {
  const RecipesEvent();

  @override
  List<Object?> get props => [];
}

class LoadRecipesEvent extends RecipesEvent {
  const LoadRecipesEvent();
}

class UpdateRecipeLibraryFlagsEvent extends RecipesEvent {
  final String recipeId;
  final bool favorite;
  final bool rescue;

  const UpdateRecipeLibraryFlagsEvent({
    required this.recipeId,
    required this.favorite,
    required this.rescue,
  });

  @override
  List<Object?> get props => [recipeId, favorite, rescue];
}
