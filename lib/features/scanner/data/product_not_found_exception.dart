import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

/// No source could turn the barcode into a food with nutrition values.
class ProductNotFoundException implements Exception {
  /// What is known without the nutrition, if anything: an Open Food Facts
  /// record with no values, or a METRO product missing some. The not-found
  /// screen names the product from it and seeds the new food with it.
  final MealEntity? partial;

  ProductNotFoundException({this.partial});
}
