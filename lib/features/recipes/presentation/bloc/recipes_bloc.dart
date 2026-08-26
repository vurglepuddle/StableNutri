import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_all_recipes_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_library_item_usecase.dart';

part 'recipes_event.dart';
part 'recipes_state.dart';

class RecipesBloc extends Bloc<RecipesEvent, RecipesState> {
  final GetAllRecipesUseCase _getAllRecipesUseCase;
  final UpdateLibraryItemUsecase? _updateLibraryItemUsecase;

  RecipesBloc(this._getAllRecipesUseCase, [this._updateLibraryItemUsecase])
    : super(const RecipesInitial()) {
    on<LoadRecipesEvent>((event, emit) {
      emit(const RecipesLoading());
      try {
        final recipes = _getAllRecipesUseCase.getAll();
        recipes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        emit(RecipesLoaded(recipes));
      } catch (e) {
        emit(RecipesFailed(e.toString()));
      }
    });
    on<UpdateRecipeLibraryFlagsEvent>((event, emit) async {
      try {
        await _updateLibraryItemUsecase?.updateRecipe(
          event.recipeId,
          favorite: event.favorite,
          rescue: event.rescue,
        );
        final recipes = _getAllRecipesUseCase.getAll()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        emit(RecipesLoaded(recipes));
      } catch (e) {
        emit(RecipesFailed(e.toString()));
      }
    });
  }
}
