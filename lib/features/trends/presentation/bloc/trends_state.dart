part of 'trends_bloc.dart';

abstract class TrendsState extends Equatable {
  const TrendsState();

  @override
  List<Object?> get props => [];
}

class TrendsInitial extends TrendsState {
  const TrendsInitial();
}

class TrendsLoading extends TrendsState {
  const TrendsLoading();
}

class TrendsLoaded extends TrendsState {
  final int rangeDays; // the selected range chip: 7, 30, 90, or 0 for "All"
  final int windowDays; // effective span the charts plot over (resolved "All")
  final List<TrackedDayEntity> days; // tracked days over the selected window
  final List<TrackedDayEntity> priorWeek; // the 7 days before this week
  final List<WeightLogEntity> weight; // full weight history, windowed in the UI
  final List<BodyMeasurementLogEntity> measurements;
  final BodyWeightUnit bodyWeightUnit;
  final bool usesImperialLengthUnits;
  final double weightCorridorLowerKg;
  final double weightCorridorUpperKg;
  final Map<DateTime, int> waterByDay; // ml logged per calendar day
  final int waterGoalMl;

  const TrendsLoaded({
    required this.rangeDays,
    required this.windowDays,
    required this.days,
    required this.priorWeek,
    required this.weight,
    required this.measurements,
    required this.bodyWeightUnit,
    required this.usesImperialLengthUnits,
    required this.weightCorridorLowerKg,
    required this.weightCorridorUpperKg,
    required this.waterByDay,
    required this.waterGoalMl,
  });

  @override
  List<Object?> get props => [
    rangeDays,
    windowDays,
    days,
    priorWeek,
    weight,
    measurements,
    bodyWeightUnit,
    usesImperialLengthUnits,
    weightCorridorLowerKg,
    weightCorridorUpperKg,
    waterByDay,
    waterGoalMl,
  ];
}

class TrendsFailed extends TrendsState {
  final String message;

  const TrendsFailed(this.message);

  @override
  List<Object?> get props => [message];
}
