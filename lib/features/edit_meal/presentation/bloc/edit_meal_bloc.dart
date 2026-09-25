import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/custom_meals_bloc.dart';

part 'edit_meal_state.dart';

part 'edit_meal_event.dart';

/// Whether a food is measured by weight or volume, which the food form
/// shows as g or ml. A food counted in servings, such as a Lifesum import
/// logged by the portion, is not; its units are kept as they are.
bool isMeasuredByWeightOrVolume(String? unit) {
  final value = unit?.trim().toLowerCase() ?? '';
  return value.isEmpty ||
      value == 'g/ml' ||
      value == 'gml' ||
      MealEntity.solidUnits.contains(value) ||
      MealEntity.liquidUnits.contains(value);
}

/// A food's nutrition per 100 g or ml, as the food form collected it. The
/// four main values are always set (a blank field means none); a blank
/// micronutrient stays unknown.
typedef FoodNutritionPer100 = ({
  double kcal,
  double carbs,
  double fat,
  double protein,
  double? fiber,
  double? saturatedFat,
  double? sugars,
  double? sodium,
  double? calcium,
  double? iron,
  double? potassium,
  double? magnesium,
  double? vitaminD,
  double? vitaminB12,
});

class EditMealBloc extends Bloc<EditMealEvent, EditMealState> {
  final GetConfigUsecase _getConfigUsecase;
  final CustomMealDataSource _customMealDataSource; // #267

  EditMealBloc(this._getConfigUsecase, this._customMealDataSource)
    : super(EditMealInitial()) {
    on<InitializeEditMealEvent>((event, emit) async {
      emit(EditMealLoadingState());

      final config = await _getConfigUsecase.getConfig();
      emit(
        EditMealLoadedState(usesImperialUnits: config.usesImperialFoodUnits),
      );
    });
  }

  /// The edited food. [unit] is `g` or `ml` and [servingQuantity] how many
  /// of them make one serving (null for none). A null [unit] keeps a food
  /// that is counted in servings, such as a Lifesum import, measured as it
  /// was. Nutrients the form does not show are carried over unchanged.
  MealEntity createNewMealEntity(
    MealEntity oldMealEntity, {
    required String name,
    required String brands,
    required String? unit,
    required double? servingQuantity,
    required FoodNutritionPer100 per100,
    String? barcodeOverride,
    String? localImagePathOverride,
    bool clearLocalImagePath = false,
  }) {
    final old = oldMealEntity.nutriments;
    final nutriments = MealNutrimentsEntity(
      energyKcal100: per100.kcal,
      carbohydrates100: per100.carbs,
      fat100: per100.fat,
      proteins100: per100.protein,
      sugars100: per100.sugars,
      saturatedFat100: per100.saturatedFat,
      fiber100: per100.fiber,
      monounsaturatedFat100: old.monounsaturatedFat100,
      polyunsaturatedFat100: old.polyunsaturatedFat100,
      transFat100: old.transFat100,
      cholesterol100: old.cholesterol100,
      sodium100: per100.sodium,
      potassium100: per100.potassium,
      magnesium100: per100.magnesium,
      calcium100: per100.calcium,
      iron100: per100.iron,
      zinc100: old.zinc100,
      phosphorus100: old.phosphorus100,
      vitaminA100: old.vitaminA100,
      vitaminC100: old.vitaminC100,
      vitaminD100: per100.vitaminD,
      vitaminB6100: old.vitaminB6100,
      vitaminB12100: per100.vitaminB12,
      niacin100: old.niacin100,
    );

    final keepsUnits = unit == null;
    // A serving description ("1 slice (25 g)") only survives while it still
    // describes the serving; otherwise the label is built from the numbers.
    final servingUnchanged =
        keepsUnits ||
        (unit == oldMealEntity.mealUnit &&
            servingQuantity == oldMealEntity.scalableServingQuantity);

    return MealEntity(
      // #167: a user-typed or scanned barcode wins over whatever came
      // from the originating OFF/FDC record, but only when the override
      // was actually supplied.
      code: barcodeOverride ?? oldMealEntity.code,
      name: name.trim().toStringOrNull(),
      brands: brands.trim().toStringOrNull(),
      url: oldMealEntity.url,
      thumbnailImageUrl: oldMealEntity.thumbnailImageUrl,
      mainImageUrl: oldMealEntity.mainImageUrl,
      mealQuantity: oldMealEntity.mealQuantity,
      mealUnit: keepsUnits ? oldMealEntity.mealUnit : unit,
      servingQuantity: keepsUnits
          ? oldMealEntity.servingQuantity
          : servingQuantity,
      // One unit for the food and its serving (#495): "Serving (50 g)".
      servingUnit: keepsUnits ? oldMealEntity.servingUnit : unit,
      servingSize: servingUnchanged ? oldMealEntity.servingSize : null,
      nutriments: nutriments,
      source: oldMealEntity.source,
      backendSource: oldMealEntity.backendSource,
      isFavorite: oldMealEntity.isFavorite,
      isRescue: oldMealEntity.isRescue,
      // #64 follow-up: a freshly-picked local photo wins over what was
      // on the old entity; a clear flag means the user removed the
      // photo and the slug should be wiped from the saved meal.
      localImagePath: clearLocalImagePath
          ? null
          : (localImagePathOverride ?? oldMealEntity.localImagePath),
      // The user's own values: an Open Food Facts search result must not be
      // "completed" from the server over them afterwards.
      detailed: true,
    );
  }

  /// Persist custom meal template so it appears in Recent Meals before first log (#267)
  Future<void> saveCustomMeal(MealEntity mealEntity) async {
    await _customMealDataSource.saveCustomMeal(
      MealDBO.fromMealEntity(mealEntity),
    );

    // Tell the Library its list is out of date.
    //
    // [CustomMealsBloc] is a lazy singleton and [RecipesPage] lives inside
    // MainScreen's IndexedStack, so its `initState` — the only thing that
    // loads the list — runs once for the life of the app. Every other write
    // path either returns *into* the Library (which reloads on the way back)
    // or notifies it explicitly, as the shared-meal importer does. A meal
    // saved from the create-and-log path did neither, so it stayed invisible
    // until the app was next resumed, which reads as the save having failed.
    //
    // Guarded rather than assumed: this is a cosmetic refresh, and a unit
    // test that builds the bloc without a full locator must not have its
    // save turned into a "couldn't save meal" error by a missing dependency.
    if (locator.isRegistered<CustomMealsBloc>()) {
      locator<CustomMealsBloc>().add(LoadCustomMealsEvent());
    }
  }
}
