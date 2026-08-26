import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_nutriments_dbo.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/domain/usecase/update_library_item_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

import '../helpers/fake_hive_db_provider.dart';
import '../helpers/hive_test_setup.dart';

MealNutrimentsDBO _nutriments() => MealNutrimentsDBO(
  energyKcal100: 100,
  carbohydrates100: 10,
  fat100: 2,
  proteins100: 5,
  sugars100: null,
  saturatedFat100: null,
  fiber100: null,
);

MealDBO _meal({String name = 'Soup', bool? favorite, bool? rescue}) => MealDBO(
  code: 'food-1',
  name: name,
  brands: null,
  thumbnailImageUrl: null,
  mainImageUrl: null,
  url: null,
  mealQuantity: '100',
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: _nutriments(),
  source: MealSourceDBO.off,
  isFavorite: favorite,
  isRescue: rescue,
);

RecipeDBO _recipe({String name = 'Toast', bool? favorite, bool? rescue}) =>
    RecipeDBO(
      id: 'recipe-1',
      name: name,
      description: null,
      ingredients: const [],
      totalWeightG: 100,
      aggregatedNutrimentsPer100: _nutriments(),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      servingsCount: null,
      tags: null,
      imagePath: null,
      isFavorite: favorite,
      isRescue: rescue,
    );

void main() {
  late Box<MealDBO> mealBox;
  late Box<RecipeDBO> recipeBox;
  late CustomMealDataSource meals;
  late RecipeDataSource recipes;
  late UpdateLibraryItemUsecase usecase;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Hive.init('.');
    registerHiveAdaptersOnce();
  });

  setUp(() async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    mealBox = await Hive.openBox<MealDBO>('library_meals_$suffix');
    recipeBox = await Hive.openBox<RecipeDBO>('library_recipes_$suffix');
    final provider = FakeHiveDBProvider(
      customMealBox: mealBox,
      recipeBox: recipeBox,
    );
    meals = CustomMealDataSource(provider);
    recipes = RecipeDataSource(provider);
    usecase = UpdateLibraryItemUsecase(meals, recipes);
  });

  tearDown(() async {
    await mealBox.deleteFromDisk();
    await recipeBox.deleteFromDisk();
  });

  test('older saved meals decode with both Library labels off', () {
    final entity = MealEntity.fromMealDBO(_meal());

    expect(entity.isFavorite, isFalse);
    expect(entity.isRescue, isFalse);
  });

  test('labelling a remote food saves its complete snapshot', () async {
    final remote = MealEntity.fromMealDBO(_meal());

    await usecase.updateMeal(remote, favorite: true, rescue: true);

    final stored = meals.getAllCustomMeals().single;
    expect(stored.code, 'food-1');
    expect(stored.nutriments.energyKcal100, 100);
    expect(stored.isFavorite, isTrue);
    expect(stored.isRescue, isTrue);
  });

  test('editing a saved meal preserves its Library labels', () async {
    await meals.saveCustomMeal(_meal(favorite: true, rescue: true));

    await meals.saveCustomMeal(_meal(name: 'Updated soup'));

    final stored = meals.getAllCustomMeals().single;
    expect(stored.name, 'Updated soup');
    expect(stored.isFavorite, isTrue);
    expect(stored.isRescue, isTrue);
  });

  test('recipe labels can be cleared without deleting the recipe', () async {
    await recipes.saveRecipe(_recipe(favorite: true, rescue: true));

    await usecase.updateRecipe('recipe-1', favorite: false, rescue: false);

    final stored = recipes.getRecipeById('recipe-1')!;
    expect(stored.isFavorite, isFalse);
    expect(stored.isRescue, isFalse);
    expect(recipes.getAllRecipes(), hasLength(1));
  });

  test('Library labels round-trip through backup JSON', () {
    final mealJson =
        jsonDecode(jsonEncode(_meal(favorite: true, rescue: true).toJson()))
            as Map<String, dynamic>;
    final recipeJson =
        jsonDecode(jsonEncode(_recipe(favorite: true, rescue: false).toJson()))
            as Map<String, dynamic>;

    final meal = MealDBO.fromJson(mealJson);
    final recipe = RecipeDBO.fromJson(recipeJson);

    expect(meal.isFavorite, isTrue);
    expect(meal.isRescue, isTrue);
    expect(recipe.isFavorite, isTrue);
    expect(recipe.isRescue, isFalse);
  });
}
