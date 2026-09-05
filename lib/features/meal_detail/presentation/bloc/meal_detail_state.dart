part of 'meal_detail_bloc.dart';

abstract class MealDetailState extends Equatable {
  final String totalQuantityConverted;
  final double totalKcal;
  final double totalCarbs;
  final double totalFat;
  final double totalProtein;

  final String selectedUnit;

  final double dayKcalConsumed;
  final double dayKcalGoal;

  /// Full product record once a thin OFF search result has been hydrated;
  /// null until then. The screen swaps the displayed meal for this when it
  /// arrives so serving options and micronutrients appear.
  final MealEntity? hydratedMeal;

  /// True while the hydration network call is in flight.
  final bool isHydrating;

  const MealDetailState({
    required this.totalQuantityConverted,
    this.totalKcal = 0,
    this.totalCarbs = 0,
    this.totalFat = 0,
    this.totalProtein = 0,
    required this.selectedUnit,
    this.dayKcalConsumed = 0,
    this.dayKcalGoal = 0,
    this.hydratedMeal,
    this.isHydrating = false,
  });

  @override
  List<Object?> get props => [
    totalQuantityConverted,
    totalKcal,
    totalCarbs,
    totalFat,
    totalProtein,
    selectedUnit,
    dayKcalConsumed,
    dayKcalGoal,
    hydratedMeal,
    isHydrating,
  ];

  MealDetailInitial copyWith({
    String? totalQuantityConverted,
    double? totalKcal,
    double? totalCarbs,
    double? totalFat,
    double? totalProtein,
    String? selectedUnit,
    double? dayKcalConsumed,
    double? dayKcalGoal,
    MealEntity? hydratedMeal,
    bool? isHydrating,
  }) {
    return MealDetailInitial(
      totalQuantityConverted:
          totalQuantityConverted ?? this.totalQuantityConverted,
      totalKcal: totalKcal ?? this.totalKcal,
      totalCarbs: totalCarbs ?? this.totalCarbs,
      totalFat: totalFat ?? this.totalFat,
      totalProtein: totalProtein ?? this.totalProtein,
      selectedUnit: selectedUnit ?? this.selectedUnit,
      dayKcalConsumed: dayKcalConsumed ?? this.dayKcalConsumed,
      dayKcalGoal: dayKcalGoal ?? this.dayKcalGoal,
      hydratedMeal: hydratedMeal ?? this.hydratedMeal,
      isHydrating: isHydrating ?? this.isHydrating,
    );
  }
}

class MealDetailInitial extends MealDetailState {
  const MealDetailInitial({
    required super.totalQuantityConverted,
    super.totalKcal,
    super.totalCarbs,
    super.totalFat,
    super.totalProtein,
    required super.selectedUnit,
    super.dayKcalConsumed,
    super.dayKcalGoal,
    super.hydratedMeal,
    super.isHydrating,
  });
}
