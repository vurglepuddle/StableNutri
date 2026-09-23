part of 'home_bloc.dart';

abstract class HomeState extends Equatable {
  const HomeState();
}

class HomeInitial extends HomeState {
  @override
  List<Object> get props => [];
}

class HomeLoadingState extends HomeState {
  @override
  List<Object?> get props => [];
}

/// One logical day on Today: its lists, and the totals the dashboard and the
/// water card show for it.
class HomeDay extends Equatable {
  final DateTime day;
  final List<IntakeEntity> breakfastIntakeList;
  final List<IntakeEntity> lunchIntakeList;
  final List<IntakeEntity> dinnerIntakeList;
  final List<IntakeEntity> snackIntakeList;
  final List<UserActivityEntity> userActivityList;
  final DailySteps? dailySteps;
  // The goal includes the day's own activity, so it differs day to day.
  final double totalKcalDaily;
  final double totalKcalSupplied;
  final double totalKcalBurned;
  final double dailyIntakeLowerKcal;
  final double dailyIntakeUpperKcal;
  final double totalCarbsIntake;
  final double totalFatsIntake;
  final double totalProteinsIntake;
  final double totalCarbsGoal;
  final double totalFatsGoal;
  final double totalProteinsGoal;
  // #150: recommended kcal target for each meal section, derived from the
  // daily goal and the share configured under Settings → Calculations.
  final double breakfastKcalTarget;
  final double lunchKcalTarget;
  final double dinnerKcalTarget;
  final double snackKcalTarget;
  // #32: water summed across every entry within the logical day.
  final int waterMl;
  final List<WaterIntakeEntity> waterIntakes;

  const HomeDay({
    required this.day,
    required this.breakfastIntakeList,
    required this.lunchIntakeList,
    required this.dinnerIntakeList,
    required this.snackIntakeList,
    required this.userActivityList,
    this.dailySteps,
    required this.totalKcalDaily,
    required this.totalKcalSupplied,
    required this.totalKcalBurned,
    required this.dailyIntakeLowerKcal,
    required this.dailyIntakeUpperKcal,
    required this.totalCarbsIntake,
    required this.totalFatsIntake,
    required this.totalProteinsIntake,
    required this.totalCarbsGoal,
    required this.totalFatsGoal,
    required this.totalProteinsGoal,
    required this.breakfastKcalTarget,
    required this.lunchKcalTarget,
    required this.dinnerKcalTarget,
    required this.snackKcalTarget,
    required this.waterMl,
    required this.waterIntakes,
  });

  bool get isEmpty =>
      breakfastIntakeList.isEmpty &&
      lunchIntakeList.isEmpty &&
      dinnerIntakeList.isEmpty &&
      snackIntakeList.isEmpty &&
      userActivityList.isEmpty;

  @override
  List<Object?> get props => [
    day,
    breakfastIntakeList,
    lunchIntakeList,
    dinnerIntakeList,
    snackIntakeList,
    userActivityList,
    dailySteps,
    totalKcalDaily,
    totalKcalSupplied,
    totalKcalBurned,
    dailyIntakeLowerKcal,
    dailyIntakeUpperKcal,
    totalCarbsGoal,
    totalFatsGoal,
    totalProteinsGoal,
    waterMl,
    waterIntakes,
  ];
}

class HomeLoadedState extends HomeState {
  /// The logical day Today shows, and the actual logical today.
  final DateTime selectedDay;
  final DateTime today;

  /// The shown day, its neighbours (so a swipe reveals them already filled)
  /// and today (for the launcher widget).
  final Map<DateTime, HomeDay> days;

  final bool showDisclaimerDialog;
  final double weightCorridorLowerKg;
  final double weightCorridorUpperKg;
  // Food serving units (g/oz). Sourced from the food-units preference.
  final bool usesImperialUnits;
  // Body weight unit (kg/lb/st) for the home weight chip, independent of food.
  final BodyWeightUnit bodyWeightUnit;
  final bool usesImperialLengthUnits;
  final bool showActivityTracking; // #277
  final bool showWaterTracking;
  final bool showMealMacros;
  final double userWeightKg;
  // #150 follow-up: per-meal share percentages. A 0% share signals that the
  // user has explicitly opted out of seeing that meal section (e.g. OMAD has
  // 0% snack), so the section is hidden entirely rather than showing an empty
  // header with a 0-kcal target.
  final int breakfastSharePct;
  final int lunchSharePct;
  final int dinnerSharePct;
  final int snackSharePct;
  final UserGenderEntity userGender;
  final CaloriesProfileEntity? userCaloriesProfile;
  // The user-configurable water target (Settings → Calculations) and the
  // drink size the cups pour.
  final int waterGoalMl;
  final int waterQuickAddMl;

  const HomeLoadedState({
    required this.selectedDay,
    required this.today,
    required this.days,
    required this.showDisclaimerDialog,
    required this.weightCorridorLowerKg,
    required this.weightCorridorUpperKg,
    required this.usesImperialUnits,
    required this.bodyWeightUnit,
    this.usesImperialLengthUnits = false,
    required this.userWeightKg,
    required this.breakfastSharePct,
    required this.lunchSharePct,
    required this.dinnerSharePct,
    required this.snackSharePct,
    required this.userGender,
    required this.userCaloriesProfile,
    required this.waterGoalMl,
    this.waterQuickAddMl = 250,
    this.showActivityTracking = true,
    this.showWaterTracking = true,
    this.showMealMacros = true,
  });

  /// The shown day's data. Always loaded alongside the state.
  HomeDay get day => days[selectedDay]!;

  bool get isToday => selectedDay == today;

  /// The same state showing [newDay], which must already be in [days].
  HomeLoadedState showing(DateTime newDay) => HomeLoadedState(
    selectedDay: newDay,
    today: today,
    days: days,
    showDisclaimerDialog: showDisclaimerDialog,
    weightCorridorLowerKg: weightCorridorLowerKg,
    weightCorridorUpperKg: weightCorridorUpperKg,
    usesImperialUnits: usesImperialUnits,
    bodyWeightUnit: bodyWeightUnit,
    usesImperialLengthUnits: usesImperialLengthUnits,
    userWeightKg: userWeightKg,
    breakfastSharePct: breakfastSharePct,
    lunchSharePct: lunchSharePct,
    dinnerSharePct: dinnerSharePct,
    snackSharePct: snackSharePct,
    userGender: userGender,
    userCaloriesProfile: userCaloriesProfile,
    waterGoalMl: waterGoalMl,
    waterQuickAddMl: waterQuickAddMl,
    showActivityTracking: showActivityTracking,
    showWaterTracking: showWaterTracking,
    showMealMacros: showMealMacros,
  );

  @override
  List<Object?> get props => [
    selectedDay,
    today,
    days,
    showDisclaimerDialog,
    usesImperialUnits,
    bodyWeightUnit,
    usesImperialLengthUnits,
    userWeightKg,
    weightCorridorLowerKg,
    weightCorridorUpperKg,
    breakfastSharePct,
    lunchSharePct,
    dinnerSharePct,
    snackSharePct,
    waterGoalMl,
    waterQuickAddMl,
    showActivityTracking,
    showWaterTracking,
    showMealMacros,
  ];
}
