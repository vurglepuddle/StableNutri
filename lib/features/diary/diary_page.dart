import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/diary_table_calendar.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The month calendar. Picking a day opens it on Today, which shows the day
/// itself, so nothing about the day is repeated here.
///
/// The day details this page used to show (DayInfoWidget and its nutrient
/// circles) are kept for the weekly view planned for Trends.
class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> with WidgetsBindingObserver {
  late DiaryBloc _diaryBloc;
  late HomeBloc _homeBloc;

  // #292: Extended from 356 days (~1 year) to 5 years so old entries are never truncated
  static const _calendarDurationDays = Duration(days: 365 * 5);

  // Derive today from the DiaryBloc so the calendar honours the configured
  // day-start offset (otherwise between midnight and e.g. 4 am Home and Diary
  // disagree on which day is "today").
  DateTime get _currentDate => _diaryBloc.currentDay;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    _diaryBloc = locator<DiaryBloc>();
    _homeBloc = locator<HomeBloc>();
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // #139: refresh on resume so a day-boundary change made while the app
    // was in the background is picked up.
    if (state == AppLifecycleState.resumed) {
      _diaryBloc.add(const LoadDiaryYearEvent());
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiaryBloc, DiaryState>(
      bloc: _diaryBloc,
      builder: (context, state) {
        if (state is DiaryInitial) {
          _diaryBloc.add(const LoadDiaryYearEvent());
        } else if (state is DiaryLoadingState) {
          return const Center(child: CircularProgressIndicator());
        } else if (state is DiaryLoadedState) {
          return _getLoadedContent(state.trackedDayMap);
        }
        return const SizedBox();
      },
    );
  }

  Widget _getLoadedContent(Map<String, TrackedDayEntity> trackedDaysMap) {
    final shownDay = _homeBloc.selectedDay;
    return ListView(
      padding: const EdgeInsets.only(bottom: Dimens.spacing16),
      children: [
        DiaryTableCalendar(
          trackedDaysMap: trackedDaysMap,
          onDateSelected: (day, _) => _showOnToday(day),
          calendarDurationDays: _calendarDurationDays,
          currentDate: _currentDate,
          selectedDate: shownDay,
          focusedDate: shownDay,
        ),
        const SizedBox(height: Dimens.spacing8),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.today_rounded),
            label: Text(S.of(context).homeBackToTodayLabel),
            onPressed: _backToToday,
          ),
        ),
      ],
    );
  }

  void _showOnToday(DateTime day) {
    final picked = DateTime(day.year, day.month, day.day);
    if (DateUtils.isSameDay(picked, _currentDate)) {
      _backToToday();
      return;
    }
    _homeBloc.add(SelectDayEvent(picked));
    Navigator.of(context).pop();
  }

  void _backToToday() {
    _homeBloc.add(const ShowTodayEvent());
    Navigator.of(context).pop();
  }
}
