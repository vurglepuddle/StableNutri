part of 'meal_detail_bloc.dart';

abstract class MealDetailEvent extends Equatable {
  const MealDetailEvent();
}

class UpdateKcalEvent extends MealDetailEvent {
  final MealEntity meal;
  final double? totalCarbs;
  final double? totalFat;
  final double? totalProtein;
  final String? totalQuantity;
  final String? selectedUnit;

  const UpdateKcalEvent({
    required this.meal,
    this.totalCarbs,
    this.totalFat,
    this.totalProtein,
    this.totalQuantity,
    this.selectedUnit,
  });

  @override
  List<Object?> get props => [
    meal,
    totalCarbs,
    totalFat,
    totalProtein,
    totalQuantity,
    selectedUnit,
  ];
}

class LoadDailyTotalsEvent extends MealDetailEvent {
  final DateTime day;

  const LoadDailyTotalsEvent(this.day);

  @override
  List<Object?> get props => [day];
}

/// Keep a selected remote food in the local Library and fetch the full OFF
/// record when needed for serving options and micronutrients. Saved full
/// records take precedence, including user corrections.
class HydrateMealEvent extends MealDetailEvent {
  final MealEntity meal;

  const HydrateMealEvent(this.meal);

  @override
  List<Object?> get props => [meal];
}
