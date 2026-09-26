import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/scanner/data/metro_data_source.dart';
import 'package:opennutritracker/features/scanner/data/product_not_found_exception.dart';

/// Looks up the meal corresponding to a scanned barcode. Resolution order:
///
///   1. **User's own custom meals** — a custom meal the user has saved
///      with a barcode (#167) wins over remote data, because the user
///      explicitly created the entry and a matching scan should pull
///      that exact saved record back.
///   2. **Cached full OFF lookup** — makes repeat scans instant and works
///      offline. Only full (hydrated/scanned) cache entries count; a thin
///      Search-a-licious search result under the same code is skipped so the
///      scan still pulls the complete product.
///   3. **Live OFF API** — only when nothing local matches. The
///      successful result is then written to the cache for next time.
///   4. **METRO by barcode** — when OFF has no record, or a record without a
///      single nutrition value (common for Russian products). A METRO
///      product with all four main values stands in for it and is cached
///      the same way. Anything less ends in [ProductNotFoundException]
///      carrying what is known, for the not-found screen to build on.
///
/// Step 4 and the "no values is no result" rule apply only when a
/// [MetroDataSource] is supplied; without one the lookup behaves as it did
/// before METRO existed.
///
/// Recipes do not participate in this lookup. Recipes are compositions
/// of meals, not single scannable products, so attaching a barcode to a
/// recipe was a model error in the first cut of #167 — corrected here.
/// A user who wants a scan to recall a saved meal should set the
/// barcode on the meal itself via Edit Meal.
class SearchProductByBarcodeUseCase {
  static final _log = Logger('SearchProductByBarcodeUseCase');

  final ProductsRepository _productsRepository;
  final CustomMealDataSource _customMealDataSource;
  final RemoteSearchCacheDataSource _cachedOffMealDataSource;
  final MetroDataSource? _metroDataSource;
  final GetConfigUsecase? _getConfigUsecase;

  SearchProductByBarcodeUseCase(
    this._productsRepository,
    this._customMealDataSource,
    this._cachedOffMealDataSource, {
    MetroDataSource? metroDataSource,
    GetConfigUsecase? getConfigUsecase,
  }) : _metroDataSource = metroDataSource,
       _getConfigUsecase = getConfigUsecase;

  /// [onStage] hears when the lookup leaves the device and moves between
  /// sources, so a slow network can be explained to the user.
  Future<MealEntity> searchProductByBarcode(
    String barcode, {
    ValueChanged<BarcodeLookupStage>? onStage,
  }) async {
    final customMatch = _customMealDataSource
        .getAllCustomMeals()
        .where((dbo) => dbo.code != null && dbo.code == barcode)
        .firstOrNull;
    if (customMatch != null) {
      return MealEntity.fromMealDBO(customMatch);
    }

    final cachedMatch = _cachedOffMealDataSource.getDetailedByBarcode(barcode);
    if (cachedMatch != null) {
      final cached = MealEntity.fromMealDBO(cachedMatch);
      if (!_needsHelp(cached)) return cached;
    }

    MealEntity? partial;
    onStage?.call(BarcodeLookupStage.openFoodFacts);
    try {
      final remote = await _productsRepository.getOFFProductByBarcode(barcode);
      if (!_needsHelp(remote)) {
        await _cachedOffMealDataSource.cache(MealDBO.fromMealEntity(remote));
        return remote;
      }
      partial = remote;
    } on ProductNotFoundException {
      if (_metroDataSource == null) rethrow;
    }

    final metro = await _findInMetro(barcode, onStage);
    if (metro != null && metro.hasAllNutrition) {
      final meal = _withFallbackImage(
        metro.toMealEntity(code: barcode),
        partial,
      );
      await _cachedOffMealDataSource.cache(MealDBO.fromMealEntity(meal));
      return meal;
    }
    throw ProductNotFoundException(
      partial: metro != null && metro.hasAnyNutrition
          ? _withFallbackImage(metro.toMealEntity(code: barcode), partial)
          : partial ?? metro?.toMealEntity(code: barcode),
    );
  }

  /// A record without a single main value only looks like a result: logging
  /// it would add zero calories.
  bool _needsHelp(MealEntity meal) =>
      _metroDataSource != null && !hasAnyMainNutrient(meal.nutriments);

  Future<MetroProduct?> _findInMetro(
    String barcode,
    ValueChanged<BarcodeLookupStage>? onStage,
  ) async {
    final metro = _metroDataSource;
    final config = await _getConfigUsecase?.getConfig();
    if (metro == null ||
        !(config?.isFoodSourceEnabled(MetroDataSource.sourceCode) ?? true)) {
      return null;
    }
    onStage?.call(BarcodeLookupStage.metro);
    try {
      final found = await metro.findByBarcode(barcode);
      return found.where((p) => p.hasAllNutrition).firstOrNull ??
          found.firstOrNull;
    } catch (error) {
      // METRO is a bonus; without it the scan ends where it did before.
      _log.warning('METRO barcode lookup failed: $error');
      return null;
    }
  }

  /// METRO has photos for nearly everything; when it does not, the Open
  /// Food Facts record it replaces may.
  MealEntity _withFallbackImage(MealEntity meal, MealEntity? other) {
    if (meal.thumbnailImageUrl != null || other?.thumbnailImageUrl == null) {
      return meal;
    }
    return MealEntity(
      code: meal.code,
      name: meal.name,
      brands: meal.brands,
      thumbnailImageUrl: other!.thumbnailImageUrl,
      mainImageUrl: other.mainImageUrl,
      url: meal.url,
      mealQuantity: meal.mealQuantity,
      mealUnit: meal.mealUnit,
      servingQuantity: meal.servingQuantity,
      servingUnit: meal.servingUnit,
      servingSize: meal.servingSize,
      nutriments: meal.nutriments,
      source: meal.source,
      backendSource: meal.backendSource,
      detailed: meal.detailed,
    );
  }
}

/// Where a barcode lookup has got to; the saved foods and the cache are
/// [local] and answer at once.
enum BarcodeLookupStage { local, openFoodFacts, metro }

/// Whether any of energy, carbohydrate, fat or protein is known.
bool hasAnyMainNutrient(MealNutrimentsEntity n) =>
    n.energyKcal100 != null ||
    n.carbohydrates100 != null ||
    n.fat100 != null ||
    n.proteins100 != null;
