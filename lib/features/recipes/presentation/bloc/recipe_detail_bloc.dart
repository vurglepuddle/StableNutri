import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/delete_recipe_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_recipe_by_id_usecase.dart';

part 'recipe_detail_event.dart';
part 'recipe_detail_state.dart';

class RecipeDetailBloc extends Bloc<RecipeDetailEvent, RecipeDetailState> {
  final GetRecipeByIdUseCase _getRecipeByIdUseCase;
  final DeleteRecipeUseCase _deleteRecipeUseCase;

  RecipeDetailBloc(this._getRecipeByIdUseCase, this._deleteRecipeUseCase)
    : super(const RecipeDetailInitial()) {
    on<LoadRecipeEvent>((event, emit) {
      final recipe = _getRecipeByIdUseCase.getById(event.id);
      if (recipe == null) {
        emit(const RecipeDetailMissing());
      } else {
        emit(RecipeDetailLoaded(recipe));
      }
    });
    on<DeleteRecipeFromDetailEvent>((event, emit) async {
      final current = state;
      if (current is! RecipeDetailLoaded) return;
      await _deleteRecipeUseCase.delete(current.recipe.id);
      emit(const RecipeDetailDeleted());
    });
  }
}
