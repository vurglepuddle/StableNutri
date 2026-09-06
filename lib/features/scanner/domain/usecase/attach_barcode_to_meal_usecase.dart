import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

/// Connects a scanned-but-unknown barcode to a food the user already has.
///
/// The scanned code is stamped onto the chosen meal and the result is saved
/// to the custom-meal box, which is the first thing
/// [SearchProductByBarcodeUseCase] consults — so the next scan of that code
/// resolves locally and instantly, with no network round-trip and no 404.
///
/// The saved copy keeps its original [MealSourceEntity], images and links:
/// connecting a code is a labelling act, not a re-authoring one, and
/// discarding the provenance would lose the product photo and the source
/// URL shown on the detail screen.
///
/// Note that the code genuinely replaces whatever the meal carried before.
/// That is the intent — the user is asserting "this package is this food" —
/// and because the custom-meal box is keyed by code, a food reached under
/// two different barcodes ends up as two entries rather than one being
/// silently overwritten. That suits the real case it comes from: the same
/// product carrying different codes across regions or pack sizes.
///
/// The record lives in the local Hive box like any other custom meal, so it
/// is covered by the existing export (`ExportDataUseCase` serialises the
/// whole custom-meal box) without any further work here.
class AttachBarcodeToMealUseCase {
  final CustomMealDataSource _customMealDataSource;

  AttachBarcodeToMealUseCase(this._customMealDataSource);

  /// Returns the stored meal, so the caller can carry the connected copy
  /// straight into the logging flow instead of re-reading it.
  Future<MealEntity> attachBarcode(MealEntity meal, String barcode) async {
    final connected = meal.copyWith(code: barcode);
    await _customMealDataSource.saveCustomMeal(
      MealDBO.fromMealEntity(connected),
    );
    return connected;
  }
}
