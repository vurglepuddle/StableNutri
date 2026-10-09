part of 'recent_meal_bloc.dart';

abstract class RecentMealEvent extends Equatable {
  const RecentMealEvent();
}

class LoadRecentMealEvent extends RecentMealEvent {
  final String searchString;
  final IntakeTypeEntity? intakeType;
  final DateTime? day;

  /// an empty `searchString` will load all RecentMeal
  const LoadRecentMealEvent({
    required this.searchString,
    this.intakeType,
    this.day,
  });

  @override
  List<Object?> get props => [searchString, intakeType, day];
}
