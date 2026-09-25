import 'package:collection/collection.dart';
import 'package:opennutritracker/core/data/health/health_steps_sync.dart';
import 'package:opennutritracker/core/data/repository/daily_steps_repository.dart';
import 'package:opennutritracker/core/domain/entity/daily_steps.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/calories_profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_user_activity_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/calc/water_trim_calc.dart';
import 'package:opennutritracker/core/utils/calc/macro_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/launcher_widget_service.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';

part 'home_event.dart';

part 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final GetConfigUsecase _getConfigUsecase;
  final AddConfigUsecase _addConfigUsecase;
  final GetIntakeUsecase _getIntakeUsecase;
  final DeleteIntakeUsecase _deleteIntakeUsecase;
  final UpdateIntakeUsecase _updateIntakeUsecase;
  final GetUserActivityUsecase _getUserActivityUsecase;
  final DeleteUserActivityUsecase _deleteUserActivityUsecase;
  final AddTrackedDayUsecase _addTrackedDayUseCase;
  final GetKcalGoalUsecase _getKcalGoalUsecase;
  final GetMacroGoalUsecase _getMacroGoalUsecase;
  final UpdateUserActivityUsecase _updateUserActivityUsecase;
  final GetUserUsecase _getUserUsecase;
  final GetWaterIntakeUsecase _getWaterIntakeUsecase;
  final AddWaterIntakeUsecase _addWaterIntakeUsecase;
  final DeleteWaterIntakeUsecase _deleteWaterIntakeUsecase;
  final DailyStepsRepository? dailyStepsRepository;
  final HealthStepsSync? healthStepsSync;

  /// The logical today, as of the last load.
  DateTime currentDay = DateTime.now();

  /// The day Today shows; null follows today, across midnight too.
  DateTime? _selectedDay;
  int _loadGeneration = 0;

  /// The logical day Today shows.
  DateTime get selectedDay => _selectedDay ?? currentDay;

  /// What new food and activity are logged against: the clock time on today,
  /// as before, and the shown day's label on any other day.
  DateTime get dayForNewEntries => _selectedDay ?? DateTime.now();

  HomeBloc(
    this._getConfigUsecase,
    this._addConfigUsecase,
    this._getIntakeUsecase,
    this._deleteIntakeUsecase,
    this._updateIntakeUsecase,
    this._getUserActivityUsecase,
    this._deleteUserActivityUsecase,
    this._addTrackedDayUseCase,
    this._getKcalGoalUsecase,
    this._getMacroGoalUsecase,
    this._updateUserActivityUsecase,
    this._getUserUsecase,
    this._getWaterIntakeUsecase,
    this._addWaterIntakeUsecase,
    this._deleteWaterIntakeUsecase, {
    this.dailyStepsRepository,
    this.healthStepsSync,
  }) : super(HomeInitial()) {
    on<LoadItemsEvent>((event, emit) async {
      final generation = ++_loadGeneration;
      final widgetProfileId = LauncherWidgetService.activeProfileId;
      final widgetRevision = LauncherWidgetService.revision;
      // A refresh keeps the loaded dashboard mounted. Swapping it for the
      // spinner, even for one frame, rebuilds every card: a poured cup
      // appears already full instead of animating, and the list jumps back
      // to the top. The launcher import below spans frames on its own.
      if (event.reset || state is! HomeLoadedState) emit(HomeLoadingState());
      // Another profile starts on its own today.
      if (event.reset) _selectedDay = null;
      final widgetWaterIds = await LauncherWidgetService.importWater();
      // Steps are read per day below, so a running sync finishes first.
      await healthStepsSync?.sync();

      final config = await _getConfigUsecase.getConfig();
      final user = await _getUserUsecase.getUserData();
      final waterQuickAddMl = await _getWaterIntakeUsecase
          .getQuickAddAmountMl();
      // #139: the logical day, so day changes respect the configured
      // boundary (hours and minutes).
      final today = DayBoundaryCalc.currentLogicalDayMinutes(
        config.dayStartOffsetTotalMinutes,
      );
      currentDay = today;
      // A shown day that has become today follows today from now on.
      if (_selectedDay == today) _selectedDay = null;
      final selected = _selectedDay ?? today;

      final days = <DateTime, HomeDay>{};
      final tomorrow = _addDays(today, 1);
      for (final day in {
        _addDays(selected, -1),
        selected,
        _addDays(selected, 1),
        today,
        // For the launcher widget, which moves on at the day boundary.
        tomorrow,
      }) {
        days[day] = await _loadDay(day, config, user);
      }
      // A newer load (a later change, or a swipe to another day) supersedes
      // this one; emitting it would briefly show stale or wrong-day data.
      if (generation != _loadGeneration) return;

      emit(
        HomeLoadedState(
          selectedDay: selected,
          today: today,
          days: days,
          showDisclaimerDialog: !config.hasAcceptedDisclaimer,
          weightCorridorLowerKg: config.weightCorridorLowerKg ?? user.weightKG,
          weightCorridorUpperKg: config.weightCorridorUpperKg ?? user.weightKG,
          usesImperialUnits: config.usesImperialFoodUnits,
          bodyWeightUnit: config.bodyWeightUnit,
          usesImperialLengthUnits: config.usesImperialHeightUnits,
          showActivityTracking: config.showActivityTracking,
          showWaterTracking: config.showWaterTracking,
          showMealMacros: config.showMealMacros,
          userWeightKg: user.weightKG,
          breakfastSharePct:
              config.mealKcalSharesPct[ConfigEntity.mealKeyBreakfast] ?? 0,
          lunchSharePct:
              config.mealKcalSharesPct[ConfigEntity.mealKeyLunch] ?? 0,
          dinnerSharePct:
              config.mealKcalSharesPct[ConfigEntity.mealKeyDinner] ?? 0,
          snackSharePct:
              config.mealKcalSharesPct[ConfigEntity.mealKeySnack] ?? 0,
          userGender: user.gender,
          userCaloriesProfile: user.caloriesProfile,
          waterGoalMl: config.effectiveDailyWaterGoalMl(
            user.gender,
            caloriesProfile: user.caloriesProfile,
          ),
          waterQuickAddMl: waterQuickAddMl,
        ),
      );
      // The launcher widget always shows today, whatever day is on screen.
      final todayData = days[today]!;
      final tomorrowData = days[tomorrow]!;
      await LauncherWidgetService.publish(
        expectedProfileId: widgetProfileId,
        expectedRevision: widgetRevision,
        appliedWaterIds: widgetWaterIds,
        config: config,
        day: today,
        waterMl: todayData.waterMl,
        cupMl: waterQuickAddMl,
        foodKcal: todayData.totalKcalSupplied,
        exerciseKcal: todayData.totalKcalBurned,
        nextDay: (
          waterMl: tomorrowData.waterMl,
          foodKcal: tomorrowData.totalKcalSupplied,
          exerciseKcal: tomorrowData.totalKcalBurned,
        ),
      );
    });

    on<ShowTodayEvent>((event, emit) {
      _selectedDay = null;
      final current = state;
      if (current is HomeLoadedState) emit(current.showing(current.today));
      add(const LoadItemsEvent());
    });

    on<SelectDayEvent>((event, emit) {
      final day = DateTime(event.day.year, event.day.month, event.day.day);
      _selectedDay = day == currentDay ? null : day;
      // A day already loaded (a swiped-to neighbour) shows at once, so the
      // dashboard moves with the swipe; the load then fetches its neighbours.
      final current = state;
      if (current is HomeLoadedState && current.days.containsKey(day)) {
        emit(current.showing(day));
      }
      add(const LoadItemsEvent());
    });
  }

  double getTotalKcal(List<IntakeEntity> intakeList) =>
      intakeList.map((intake) => intake.totalKcal).toList().sum;

  /// Everything Today shows for one logical [day].
  Future<HomeDay> _loadDay(
    DateTime day,
    ConfigEntity config,
    UserEntity user,
  ) async {
    final hours = config.dayStartOffsetHours;
    final minutes = config.dayStartOffsetMinutes;
    final breakfast = await _getIntakeUsecase.getBreakfastIntakeByDay(
      day,
      dayStartOffsetHours: hours,
      dayStartOffsetMinutes: minutes,
    );
    final lunch = await _getIntakeUsecase.getLunchIntakeByDay(
      day,
      dayStartOffsetHours: hours,
      dayStartOffsetMinutes: minutes,
    );
    final dinner = await _getIntakeUsecase.getDinnerIntakeByDay(
      day,
      dayStartOffsetHours: hours,
      dayStartOffsetMinutes: minutes,
    );
    final snack = await _getIntakeUsecase.getSnackIntakeByDay(
      day,
      dayStartOffsetHours: hours,
      dayStartOffsetMinutes: minutes,
    );
    final intakes = [...breakfast, ...lunch, ...dinner, ...snack];
    final activities = await _getUserActivityUsecase.getUserActivityByDay(
      day,
      dayStartOffsetHours: hours,
      dayStartOffsetMinutes: minutes,
    );
    final burned = activities.map((activity) => activity.burnedKcal).sum;
    final water = await _getWaterIntakeUsecase.getEntriesForDay(
      day,
      dayStartOffsetTotalMinutes: config.dayStartOffsetTotalMinutes,
    );
    final kcalGoal = await _getKcalGoalUsecase.getKcalGoal(
      userEntity: user,
      totalKcalActivitiesParam: burned,
    );
    // Stored intake bounds describe the profile's base day. Activity keeps
    // its existing behaviour by shifting both edges upward. An upgraded
    // profile with no stored range resolves to the exact legacy goal.
    final baseGoal = kcalGoal - burned;
    return HomeDay(
      day: day,
      breakfastIntakeList: breakfast,
      lunchIntakeList: lunch,
      dinnerIntakeList: dinner,
      snackIntakeList: snack,
      userActivityList: activities,
      dailySteps: dailyStepsRepository?.forDay(day),
      totalKcalDaily: kcalGoal,
      totalKcalSupplied: getTotalKcal(intakes),
      totalKcalBurned: burned,
      dailyIntakeLowerKcal: (config.dailyIntakeLowerKcal ?? baseGoal) + burned,
      dailyIntakeUpperKcal: (config.dailyIntakeUpperKcal ?? baseGoal) + burned,
      totalCarbsIntake: getTotalCarbs(intakes),
      totalFatsIntake: getTotalFats(intakes),
      totalProteinsIntake: getTotalProteins(intakes),
      totalCarbsGoal: await _getMacroGoalUsecase.getCarbsGoal(kcalGoal),
      totalFatsGoal: await _getMacroGoalUsecase.getFatsGoal(kcalGoal),
      totalProteinsGoal: await _getMacroGoalUsecase.getProteinsGoal(kcalGoal),
      // #150: recommended per-meal targets from the saved shares.
      breakfastKcalTarget: config.targetKcalForMeal(
        ConfigEntity.mealKeyBreakfast,
        kcalGoal,
      ),
      lunchKcalTarget: config.targetKcalForMeal(
        ConfigEntity.mealKeyLunch,
        kcalGoal,
      ),
      dinnerKcalTarget: config.targetKcalForMeal(
        ConfigEntity.mealKeyDinner,
        kcalGoal,
      ),
      snackKcalTarget: config.targetKcalForMeal(
        ConfigEntity.mealKeySnack,
        kcalGoal,
      ),
      waterMl: water.fold<int>(0, (sum, entry) => sum + entry.amountMl),
      waterIntakes: water,
    );
  }

  static DateTime _addDays(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);

  double getTotalCarbs(List<IntakeEntity> intakeList) =>
      intakeList.map((intake) => intake.totalCarbsGram).toList().sum;

  double getTotalFats(List<IntakeEntity> intakeList) =>
      intakeList.map((intake) => intake.totalFatsGram).toList().sum;

  double getTotalProteins(List<IntakeEntity> intakeList) =>
      intakeList.map((intake) => intake.totalProteinsGram).toList().sum;

  void saveConfigData(bool acceptedDisclaimer) async {
    _addConfigUsecase.setConfigDisclaimer(acceptedDisclaimer);
  }

  Future<void> updateIntakeItem(
    String intakeId,
    Map<String, dynamic> fields,
  ) async {
    // Get old intake values
    final oldIntakeObject = await _getIntakeUsecase.getIntakeById(intakeId);
    if (oldIntakeObject == null) return;
    final dateTime = await _logicalDayOf(oldIntakeObject.dateTime);
    final newIntakeObject = await _updateIntakeUsecase.updateIntake(
      intakeId,
      fields,
    );
    if (newIntakeObject == null) return;
    if (oldIntakeObject.amount > newIntakeObject.amount) {
      // Amounts shrunk
      await _addTrackedDayUseCase.removeDayCaloriesTracked(
        dateTime,
        oldIntakeObject.totalKcal - newIntakeObject.totalKcal,
      );
      await _addTrackedDayUseCase.removeDayMacrosTracked(
        dateTime,
        carbsTracked:
            oldIntakeObject.totalCarbsGram - newIntakeObject.totalCarbsGram,
        fatTracked:
            oldIntakeObject.totalFatsGram - newIntakeObject.totalFatsGram,
        proteinTracked:
            oldIntakeObject.totalProteinsGram -
            newIntakeObject.totalProteinsGram,
      );
    } else if (newIntakeObject.amount > oldIntakeObject.amount) {
      // Amounts gained
      await _addTrackedDayUseCase.addDayCaloriesTracked(
        dateTime,
        newIntakeObject.totalKcal - oldIntakeObject.totalKcal,
      );
      await _addTrackedDayUseCase.addDayMacrosTracked(
        dateTime,
        carbsTracked:
            newIntakeObject.totalCarbsGram - oldIntakeObject.totalCarbsGram,
        fatTracked:
            newIntakeObject.totalFatsGram - oldIntakeObject.totalFatsGram,
        proteinTracked:
            newIntakeObject.totalProteinsGram -
            oldIntakeObject.totalProteinsGram,
      );
    }
    _updateDiaryPage(dateTime);
  }

  Future<void> deleteIntakeItem(IntakeEntity intakeEntity) async {
    final dateTime = await _logicalDayOf(intakeEntity.dateTime);
    await _deleteIntakeUsecase.deleteIntake(intakeEntity);
    await _addTrackedDayUseCase.removeDayCaloriesTracked(
      dateTime,
      intakeEntity.totalKcal,
    );
    await _addTrackedDayUseCase.removeDayMacrosTracked(
      dateTime,
      carbsTracked: intakeEntity.totalCarbsGram,
      fatTracked: intakeEntity.totalFatsGram,
      proteinTracked: intakeEntity.totalProteinsGram,
    );

    _updateDiaryPage(dateTime);
  }

  Future<void> deleteUserActivityItem(UserActivityEntity activityEntity) async {
    final dateTime = await _logicalDayOf(activityEntity.date);
    await _deleteUserActivityUsecase.deleteUserActivity(activityEntity);
    _addTrackedDayUseCase.reduceDayCalorieGoal(
      dateTime,
      activityEntity.burnedKcal,
    );

    final carbsAmount = MacroCalc.getTotalCarbsGoal(activityEntity.burnedKcal);
    final fatAmount = MacroCalc.getTotalFatsGoal(activityEntity.burnedKcal);
    final proteinAmount = MacroCalc.getTotalProteinsGoal(
      activityEntity.burnedKcal,
    );

    _addTrackedDayUseCase.reduceDayMacroGoals(
      dateTime,
      carbsAmount: carbsAmount,
      fatAmount: fatAmount,
      proteinAmount: proteinAmount,
    );
    _updateDiaryPage(dateTime);
    add(
      const LoadItemsEvent(),
    ); // #208: Reload home page to remove activity indicator
  }

  Future<void> updateUserActivityItem(
    UserActivityEntity activityEntity,
    double newDuration,
  ) async {
    final dateTime = await _logicalDayOf(activityEntity.date);
    final newActivity = await _updateUserActivityUsecase.updateUserActivity(
      activityEntity,
      newDuration,
    );
    assert(newActivity != null);
    final kcalDiff = newActivity!.burnedKcal - activityEntity.burnedKcal;
    if (kcalDiff > 0) {
      _addTrackedDayUseCase.increaseDayCalorieGoal(dateTime, kcalDiff);
      _addTrackedDayUseCase.increaseDayMacroGoals(
        dateTime,
        carbsAmount: MacroCalc.getTotalCarbsGoal(kcalDiff),
        fatAmount: MacroCalc.getTotalFatsGoal(kcalDiff),
        proteinAmount: MacroCalc.getTotalProteinsGoal(kcalDiff),
      );
    } else if (kcalDiff < 0) {
      _addTrackedDayUseCase.reduceDayCalorieGoal(dateTime, kcalDiff.abs());
      _addTrackedDayUseCase.reduceDayMacroGoals(
        dateTime,
        carbsAmount: MacroCalc.getTotalCarbsGoal(kcalDiff.abs()),
        fatAmount: MacroCalc.getTotalFatsGoal(kcalDiff.abs()),
        proteinAmount: MacroCalc.getTotalProteinsGoal(kcalDiff.abs()),
      );
    }
    _updateDiaryPage(dateTime);
  }

  Future<void> _updateDiaryPage(DateTime day) async {
    locator<DiaryBloc>().add(const LoadDiaryYearEvent());
    locator<CalendarDayBloc>().add(RefreshCalendarDayEvent());
  }

  /// Logs a single water intake entry and reloads the home view so the
  /// chip updates immediately. The dialog itself only owns the slider
  /// value; persistence and recomputation flow back through the bloc.
  Future<void> addWaterIntake(int amountMl) async {
    if (amountMl <= 0) return;
    final entry = WaterIntakeEntity(
      id: 'water-${DateTime.now().microsecondsSinceEpoch}',
      dateTime: await _waterMomentForShownDay(),
      amountMl: amountMl,
    );
    await _addWaterIntakeUsecase.addEntry(entry);
    add(const LoadItemsEvent());
  }

  /// Takes [amountMl] back off the day when a full cup is tapped. Entries are
  /// trimmed newest-first, so the most recent drink is undone before older
  /// ones, and a drink larger than the tapped cup is reduced rather than
  /// deleted: the total always moves by exactly one cup (or down to zero).
  ///
  /// A reduced drink is rewritten under a `water-trimmed-` id so it stops
  /// counting as "the last amount the user chose" — otherwise trimming a
  /// 700 ml entry would silently resize every cup on the card to 450 ml.
  Future<void> removeWaterIntake(int amountMl) async {
    if (amountMl <= 0) return;
    final entries = await _shownDayWater();
    final trim = WaterTrimCalc.trim(entries, amountMl);
    if (trim.isEmpty) return;
    for (final id in trim.deleteIds) {
      await _deleteWaterIntakeUsecase.deleteEntry(id);
    }
    final reducedAt = trim.reducedAt;
    if (reducedAt != null) {
      await _addWaterIntakeUsecase.addEntry(
        WaterIntakeEntity(
          id: 'water-trimmed-${DateTime.now().microsecondsSinceEpoch}',
          dateTime: reducedAt,
          amountMl: trim.reducedMl,
        ),
      );
    }
    add(const LoadItemsEvent());
  }

  /// Rolls back the most recent water entry for the configured logical
  /// day. Returns whether anything was deleted, so the dialog can react
  /// without re-reading state.
  Future<bool> undoLastWaterIntake() async {
    final entries = await _shownDayWater();
    if (entries.isEmpty) return false;
    entries.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    await _deleteWaterIntakeUsecase.deleteEntry(entries.last.id);
    add(const LoadItemsEvent());
    return true;
  }

  /// The water entries of the day Today shows.
  Future<List<WaterIntakeEntity>> _shownDayWater() async {
    final config = await _getConfigUsecase.getConfig();
    final day = _selectedDay;
    if (day == null) {
      return _getWaterIntakeUsecase.getTodayEntries(
        dayStartOffsetTotalMinutes: config.dayStartOffsetTotalMinutes,
      );
    }
    return _getWaterIntakeUsecase.getEntriesForDay(
      day,
      dayStartOffsetTotalMinutes: config.dayStartOffsetTotalMinutes,
    );
  }

  /// When a drink logged now is recorded. Today that is simply now. On any
  /// other day it is the current clock time on that day, moved to the next
  /// date when the time falls before the day boundary (with a 04:00
  /// boundary, 01:30 still belongs to the day before), so it lands inside
  /// the day's window.
  Future<DateTime> _waterMomentForShownDay() async {
    final now = DateTime.now();
    final day = _selectedDay;
    if (day == null) return now;
    final config = await _getConfigUsecase.getConfig();
    final beforeBoundary =
        now.hour * 60 + now.minute < config.dayStartOffsetTotalMinutes;
    final date = beforeBoundary ? _addDays(day, 1) : day;
    return DateTime(
      date.year,
      date.month,
      date.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
  }

  /// #139: tracked-day deltas (calories, macros) land on the logical day
  /// the entry belongs to. On Today that need not be today any more, and
  /// with a 04:30 boundary a 02:00 entry still belongs to the day before.
  /// The offset is read on each call so the latest setting wins.
  Future<DateTime> _logicalDayOf(DateTime moment) async {
    final config = await _getConfigUsecase.getConfig();
    return DayBoundaryCalc.logicalDayOfEntry(
      moment,
      config.dayStartOffsetTotalMinutes,
    );
  }
}
