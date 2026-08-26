import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';

class RecipeDataSource {
  final HiveDBProvider _db;

  RecipeDataSource(this._db);

  Box<RecipeDBO> get _recipeBox => _db.recipeBox;

  // Upsert by stable id. Recipe ids are uuids assigned at first save and
  // never change, so we can safely overwrite the matching record.
  Future<void> saveRecipe(RecipeDBO recipe) async {
    final existing = _recipeBox.values.cast<RecipeDBO?>().firstWhere(
      (r) => r?.id == recipe.id,
      orElse: () => null,
    );
    if (existing != null) {
      final merged = recipe.withLibraryFlags(
        favorite:
            (recipe.isFavorite ?? false) || (existing.isFavorite ?? false),
        rescue: (recipe.isRescue ?? false) || (existing.isRescue ?? false),
      );
      await _recipeBox.put(existing.key, merged);
    } else {
      await _recipeBox.add(recipe);
    }
  }

  List<RecipeDBO> getAllRecipes() => _recipeBox.values.toList();

  RecipeDBO? getRecipeById(String id) {
    for (final recipe in _recipeBox.values) {
      if (recipe.id == id) return recipe;
    }
    return null;
  }

  Future<RecipeDBO?> setLibraryFlags(
    String id, {
    required bool favorite,
    required bool rescue,
  }) async {
    final recipe = getRecipeById(id);
    if (recipe == null) return null;
    final updated = recipe.withLibraryFlags(favorite: favorite, rescue: rescue);
    await _recipeBox.put(recipe.key, updated);
    return updated;
  }

  Future<void> deleteRecipe(String id) async {
    final toDelete = _recipeBox.values.where((r) => r.id == id).toList();
    for (final recipe in toDelete) {
      await recipe.delete();
    }
  }
}
