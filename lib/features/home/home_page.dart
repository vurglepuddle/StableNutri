import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/empty_hint.dart';
import 'package:opennutritracker/core/presentation/widgets/low_kcal_warning_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/activity_vertial_list.dart';
import 'package:opennutritracker/core/presentation/widgets/edit_activity_dialog.dart';
import 'package:opennutritracker/core/presentation/widgets/delete_dialog.dart';
import 'package:opennutritracker/core/presentation/widgets/disclaimer_dialog.dart';
import 'package:opennutritracker/core/utils/calc/met_calc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/activity_detail/presentation/bloc/activity_detail_bloc.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/home/presentation/widgets/dashboard_widget.dart';
import 'package:opennutritracker/features/home/presentation/widgets/intake_vertical_list.dart';
import 'package:opennutritracker/features/home/presentation/widgets/fasting_home_chip.dart';
import 'package:opennutritracker/features/home/presentation/widgets/water_card.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Today, for any day. The water card and dashboard stay in place and
/// animate to the shown day's values; below them the day's meals swipe
/// sideways, the previous day to the left and the next to the right.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final log = Logger('HomePage');

  /// Page index of [_anchor]. Far from zero, so days can be paged in either
  /// direction for decades.
  static const _anchorPage = 100000;

  late HomeBloc _homeBloc;
  PageController? _pages;
  late DateTime _anchor;
  bool _disclaimerShown = false;
  bool _isIntakeDragging = false;
  bool _isActivityDragging = false;
  bool get _isDragging => _isIntakeDragging || _isActivityDragging;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    _homeBloc = locator<HomeBloc>();
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HomeBloc, HomeState>(
      bloc: _homeBloc,
      listenWhen: (previous, current) => current is HomeLoadedState,
      listener: (context, state) =>
          _followSelectedDay(state as HomeLoadedState),
      builder: (context, state) {
        if (state is HomeInitial) {
          _homeBloc.add(const LoadItemsEvent());
          return _getLoadingContent();
        } else if (state is HomeLoadedState) {
          return _getLoadedContent(context, state);
        } else {
          return _getLoadingContent();
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      log.info('App resumed');
      _refreshPageOnDayChange();
    }
    super.didChangeAppLifecycleState(state);
  }

  Widget _getLoadingContent() {
    return const Center(child: CircularProgressIndicator());
  }

  DateTime _dayForPage(int page) =>
      DateTime(_anchor.year, _anchor.month, _anchor.day + page - _anchorPage);

  int _pageForDay(DateTime day) {
    // Calendar days, not hours: a DST change must not shift the page.
    final from = DateTime.utc(_anchor.year, _anchor.month, _anchor.day);
    final to = DateTime.utc(day.year, day.month, day.day);
    return _anchorPage + to.difference(from).inDays;
  }

  /// Pages to the shown day when it changes from elsewhere: the calendar,
  /// "Back to today", or the arrows. A swipe is already on its page.
  void _followSelectedDay(HomeLoadedState state) {
    final pages = _pages;
    if (pages == null || !pages.hasClients) return;
    final target = _pageForDay(state.selectedDay);
    final current = pages.page?.round() ?? pages.initialPage;
    if (current == target) return;
    if ((current - target).abs() == 1) {
      pages.animateToPage(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      pages.jumpToPage(target);
    }
  }

  void _showDay(DateTime day) => _homeBloc.add(SelectDayEvent(day));

  Widget _getLoadedContent(BuildContext context, HomeLoadedState state) {
    if (state.showDisclaimerDialog && !_disclaimerShown) {
      _disclaimerShown = true;
      _showDisclaimerDialog(context);
    }
    if (_pages == null) {
      _anchor = state.today;
      _pages = PageController(initialPage: _pageForDay(state.selectedDay));
    }
    final day = state.day;
    return Stack(
      children: [
        NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  if (state.showWaterTracking)
                    WaterCard(
                      waterMlToday: day.waterMl,
                      waterGoalMl: state.waterGoalMl,
                      amountMl: state.waterQuickAddMl,
                    ),
                  if (state.isToday) const FastingHomeChip(),
                  const SizedBox(height: Dimens.dashboardItemGap),
                  DashboardWidget(
                    totalKcalSupplied: day.totalKcalSupplied,
                    totalKcalBurned: day.totalKcalBurned,
                    dailyIntakeLowerKcal: day.dailyIntakeLowerKcal,
                    dailyIntakeUpperKcal: day.dailyIntakeUpperKcal,
                    totalCarbsIntake: day.totalCarbsIntake,
                    totalFatsIntake: day.totalFatsIntake,
                    totalProteinsIntake: day.totalProteinsIntake,
                    totalCarbsGoal: day.totalCarbsGoal,
                    totalFatsGoal: day.totalFatsGoal,
                    totalProteinsGoal: day.totalProteinsGoal,
                  ),
                  _DayHeader(
                    day: state.selectedDay,
                    today: state.today,
                    onPrevious: () => _showDay(
                      DateTime(
                        state.selectedDay.year,
                        state.selectedDay.month,
                        state.selectedDay.day - 1,
                      ),
                    ),
                    onNext: () => _showDay(
                      DateTime(
                        state.selectedDay.year,
                        state.selectedDay.month,
                        state.selectedDay.day + 1,
                      ),
                    ),
                    onToday: () => _homeBloc.add(const ShowTodayEvent()),
                  ),
                ],
              ),
            ),
          ],
          body: PageView.builder(
            controller: _pages,
            onPageChanged: (page) => _showDay(_dayForPage(page)),
            itemBuilder: (context, page) {
              final pageDay = _dayForPage(page);
              return _buildDayPage(context, state, pageDay);
            },
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Visibility(
            visible: _isDragging,
            child: SizedBox(
              height: 70,
              child: Stack(
                children: [
                  DragTarget<IntakeEntity>(
                    onAcceptWithDetails: (data) {
                      _confirmDelete(context, data.data);
                    },
                    onLeave: (data) {
                      setState(() {
                        _isIntakeDragging = false;
                      });
                    },
                    builder: (context, candidateData, rejectedData) {
                      return Container(
                        margin: const EdgeInsets.fromLTRB(
                          Dimens.spacing16,
                          0,
                          Dimens.spacing16,
                          Dimens.spacing12,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius: Dimens.borderRadiusL,
                        ),
                        child: Center(
                          child: Icon(
                            Icons.delete_rounded,
                            size: 32,
                            color: Theme.of(context).colorScheme.onError,
                          ),
                        ),
                      );
                    },
                  ),
                  DragTarget<UserActivityEntity>(
                    onAcceptWithDetails: (data) {
                      _confirmDeleteActivity(context, data.data);
                    },
                    onLeave: (data) {
                      setState(() {
                        _isActivityDragging = false;
                      });
                    },
                    builder: (context, candidateData, rejectedData) {
                      return const SizedBox.expand();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One day's meals and activity. Neighbours of the shown day are loaded
  /// ahead, so a swipe reveals them filled in.
  Widget _buildDayPage(
    BuildContext context,
    HomeLoadedState state,
    DateTime pageDay,
  ) {
    final data = state.days[pageDay];
    if (data == null) {
      return const Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(top: Dimens.spacing48),
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final isToday = pageDay == state.today;
    // Today keeps clock times on new entries; another day gets its label.
    final entryDay = isToday ? DateTime.now() : pageDay;
    final copyIntake = isToday
        ? null
        : (IntakeEntity intake, TrackedDayEntity? _, AddMealType? type) =>
              _copyIntakeToToday(intake, type);

    Widget meal(
      int sharePct,
      String title,
      IntakeTypeEntity type,
      AddMealType addMealType,
      List<IntakeEntity> intakes,
      double target,
    ) {
      // #150 follow-up: a 0% share (e.g. OMAD sets snack to 0) hides the
      // section entirely. Already-logged intakes still count toward totals.
      if (sharePct <= 0) return const SizedBox.shrink();
      return IntakeVerticalList(
        day: entryDay,
        title: title,
        listIcon: type.getIconData(),
        addMealType: addMealType,
        intakeList: intakes,
        onDeleteIntakeCallback: onDeleteIntake,
        onItemDragCallback: onIntakeItemDrag,
        onItemTappedCallback: onIntakeItemTapped,
        onCopyIntakeCallback: copyIntake,
        usesImperialUnits: state.usesImperialUnits,
        showMealMacros: state.showMealMacros,
        mealKcalTarget: target,
      );
    }

    final s = S.of(context);
    return ListView(
      key: PageStorageKey(pageDay),
      padding: EdgeInsets.zero,
      children: [
        // Empty-day guidance: point the way to the centre + rather than
        // leaving a silent page.
        if (data.isEmpty)
          EmptyHint(
            icon: Icons.add_circle_outline_rounded,
            title: s.homeFirstMealHint,
            compact: true,
          ),
        if (CalorieGoalCalc.isBelowRecommendedDailyKcalFloor(
          goalKcal: data.totalKcalDaily,
          gender: state.userGender,
          caloriesProfile: state.userCaloriesProfile,
        ))
          LowKcalWarningCard(
            thresholdKcal: CalorieGoalCalc.recommendedDailyKcalFloor(
              gender: state.userGender,
              caloriesProfile: state.userCaloriesProfile,
            ),
          ),
        meal(
          state.breakfastSharePct,
          s.breakfastLabel,
          IntakeTypeEntity.breakfast,
          AddMealType.breakfastType,
          data.breakfastIntakeList,
          data.breakfastKcalTarget,
        ),
        meal(
          state.lunchSharePct,
          s.lunchLabel,
          IntakeTypeEntity.lunch,
          AddMealType.lunchType,
          data.lunchIntakeList,
          data.lunchKcalTarget,
        ),
        meal(
          state.dinnerSharePct,
          s.dinnerLabel,
          IntakeTypeEntity.dinner,
          AddMealType.dinnerType,
          data.dinnerIntakeList,
          data.dinnerKcalTarget,
        ),
        meal(
          state.snackSharePct,
          s.snackLabel,
          IntakeTypeEntity.snack,
          AddMealType.snackType,
          data.snackIntakeList,
          data.snackKcalTarget,
        ),
        if (state.showActivityTracking)
          ActivityVerticalList(
            day: entryDay,
            title: s.activityLabel,
            userActivityList: data.userActivityList,
            dailySteps: data.dailySteps,
            onItemLongPressedCallback: onActivityItemLongPressed,
            onItemTappedCallback: onActivityItemTapped,
            onItemDragCallback: onActivityItemDrag,
            onCopyActivityCallback: isToday ? null : _copyActivityToToday,
          ),
        const SizedBox(height: Dimens.spacing48),
      ],
    );
  }

  /// Copies a past or future day's food to today, keeping the amount.
  Future<void> _copyIntakeToToday(
    IntakeEntity intake,
    AddMealType? type,
  ) async {
    await locator<MealDetailBloc>().addIntake(
      context,
      intake.unit,
      intake.amount.toString(),
      type?.getIntakeType() ?? intake.type,
      intake.meal,
      DateTime.now(),
    );
    _homeBloc.add(const LoadItemsEvent());
  }

  /// Copies a past or future day's activity to today.
  Future<void> _copyActivityToToday(UserActivityEntity userActivity) async {
    final activity = userActivity.physicalActivityEntity;
    final activityBloc = locator<ActivityDetailBloc>();
    if (activity.isCustom) {
      // Custom activities (#70) store the user-entered kcal directly; the
      // MET formula would return zero for them.
      final kcal = userActivity.userKcal ?? userActivity.burnedKcal;
      await activityBloc.persistActivity(
        kcal.toString(),
        kcal,
        activity,
        DateTime.now(),
      );
    } else {
      final user = await locator<GetUserUsecase>().getUserData();
      await activityBloc.persistActivity(
        userActivity.duration.toString(),
        METCalc.getTotalBurnedKcal(user, activity, userActivity.duration),
        activity,
        DateTime.now(),
      );
    }
    _homeBloc.add(const LoadItemsEvent());
  }

  void onActivityItemLongPressed(
    BuildContext context,
    UserActivityEntity activityEntity,
  ) async {
    final deleteIntake = await showDialog<bool>(
      context: context,
      builder: (context) => const DeleteDialog(),
    );

    if (deleteIntake != null) {
      _homeBloc.deleteUserActivityItem(activityEntity);
      _homeBloc.add(const LoadItemsEvent());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).itemDeletedSnackbar)),
        );
      }
    }
  }

  void onIntakeItemLongPressed(
    BuildContext context,
    IntakeEntity intakeEntity,
  ) async {
    final deleteIntake = await showDialog<bool>(
      context: context,
      builder: (context) => const DeleteDialog(),
    );

    if (deleteIntake != null) {
      _homeBloc.deleteIntakeItem(intakeEntity);
      _homeBloc.add(const LoadItemsEvent());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).itemDeletedSnackbar)),
        );
      }
    }
  }

  void onIntakeItemDrag(bool isDragging) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _isIntakeDragging = isDragging;
      });
    });
  }

  void onActivityItemDrag(bool isDragging) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _isActivityDragging = isDragging;
      });
    });
  }

  void onActivityItemTapped(
    BuildContext context,
    UserActivityEntity activityEntity,
  ) async {
    final newDuration = await showDialog<double>(
      context: context,
      builder: (context) => EditActivityDialog(activityEntity: activityEntity),
    );
    if (newDuration != null) {
      await _homeBloc.updateUserActivityItem(activityEntity, newDuration);
      _homeBloc.add(const LoadItemsEvent());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).itemUpdatedSnackbar)),
        );
      }
    }
  }

  /// Opens the logged food on the food screen, with its amount and meal at
  /// the top, to change, save or remove from the day.
  void onIntakeItemTapped(
    BuildContext context,
    IntakeEntity intakeEntity,
    bool usesImperialUnits,
  ) {
    Navigator.of(context).pushNamed(
      NavigationOptions.mealDetailRoute,
      arguments: MealDetailScreenArguments(
        intakeEntity.meal,
        intakeEntity.type,
        // Only the shown day's entries can be tapped.
        _homeBloc.selectedDay,
        usesImperialUnits,
        loggedIntake: intakeEntity,
      ),
    );
  }

  void onDeleteIntake(IntakeEntity intake, TrackedDayEntity? trackedDayEntity) {
    _homeBloc.deleteIntakeItem(intake);
    _homeBloc.add(const LoadItemsEvent());
  }

  void _confirmDelete(BuildContext context, IntakeEntity intake) async {
    bool? delete = await showDialog<bool>(
      context: context,
      builder: (context) => const DeleteDialog(),
    );

    if (delete == true) {
      onDeleteIntake(intake, null);
    }
    setState(() {
      _isIntakeDragging = false;
    });
  }

  void _confirmDeleteActivity(
    BuildContext context,
    UserActivityEntity activity,
  ) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => const DeleteDialog(),
    );
    if (delete == true) {
      _homeBloc.deleteUserActivityItem(activity);
      _homeBloc.add(const LoadItemsEvent());
    }
    setState(() {
      _isActivityDragging = false;
    });
  }

  /// Show disclaimer dialog after build method
  void _showDisclaimerDialog(BuildContext context) async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final dialogConfirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return const DisclaimerDialog();
        },
      );
      if (dialogConfirmed != null) {
        _homeBloc.saveConfigData(dialogConfirmed);
        _homeBloc.add(const LoadItemsEvent());
      }
    });
  }

  /// Refresh page when day changes
  ///
  /// #139: HomeBloc.currentDay is the logical "today" (midnight of the
  /// configured day boundary). Comparing against a fresh logical "today"
  /// from the same wall clock requires knowing the offset, which we'd
  /// have to fetch from config asynchronously. Letting LoadItemsEvent
  /// re-resolve the offset and reload unconditionally on resume is the
  /// honest cheap path: it costs one config read plus a few Hive scans,
  /// and it is correct under any boundary setting.
  void _refreshPageOnDayChange() {
    _homeBloc.add(const LoadItemsEvent());
  }
}

/// The line between the fixed dashboard and the swiping day: small arrows at
/// the edges, the day's name, and a quiet way back when it isn't today.
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.today,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime day;
  final DateTime today;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final offset = DateTime.utc(
      day.year,
      day.month,
      day.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    final label = switch (offset) {
      0 => s.todayLabel,
      -1 => s.homeYesterdayLabel,
      1 => s.homeTomorrowLabel,
      _ => MaterialLocalizations.of(context).formatMediumDate(day),
    };
    final arrow = IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      color: palette.textMuted,
      tooltip: s.homePreviousDayTooltip,
      onPressed: onPrevious,
      icon: const Icon(Icons.chevron_left_rounded),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing4),
      child: Row(
        children: [
          arrow,
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (offset != 0)
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: onToday,
                    child: Text(s.homeBackToTodayLabel),
                  ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            color: palette.textMuted,
            tooltip: s.homeNextDayTooltip,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
