import 'package:opennutritracker/features/cycle/data/cycle_repository.dart';
import 'package:opennutritracker/features/cycle/domain/cycle_data.dart';
import 'package:opennutritracker/features/cycle/presentation/cycle_page.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:table_calendar/table_calendar.dart';

class DiaryTableCalendar extends StatefulWidget {
  final Function(DateTime, Map<String, TrackedDayEntity>) onDateSelected;
  final Duration calendarDurationDays;
  final DateTime focusedDate;
  final DateTime currentDate;
  final DateTime selectedDate;

  final Map<String, TrackedDayEntity> trackedDaysMap;

  const DiaryTableCalendar({
    super.key,
    required this.onDateSelected,
    required this.calendarDurationDays,
    required this.focusedDate,
    required this.currentDate,
    required this.selectedDate,
    required this.trackedDaysMap,
  });

  @override
  State<DiaryTableCalendar> createState() => _DiaryTableCalendarState();
}

class _DiaryTableCalendarState extends State<DiaryTableCalendar> {
  @override
  Widget build(BuildContext context) {
    if (!locator.isRegistered<CycleRepository>()) {
      return _calendar(context, const CycleData());
    }
    final repo = locator<CycleRepository>();
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) => Column(
        children: [
          _calendar(context, repo.data),
          if (repo.data.enabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${S.of(context).cycleRecorded} \u25cf  /  ${S.of(context).cyclePredicted} \u25cb',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _calendar(BuildContext context, CycleData cycle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final accent = Theme.of(context).colorScheme.primary;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing8,
        Dimens.spacing16,
        Dimens.spacing4,
      ),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing8,
          Dimens.spacing12,
          Dimens.spacing8,
          Dimens.spacing12,
        ),
        child: TableCalendar(
          headerStyle: HeaderStyle(
            titleCentered: true,
            formatButtonVisible: false,
            titleTextStyle:
                textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: palette.textStrong,
                ) ??
                const TextStyle(),
            leftChevronIcon: Icon(
              Icons.chevron_left_rounded,
              color: palette.textMuted,
              size: 26,
            ),
            rightChevronIcon: Icon(
              Icons.chevron_right_rounded,
              color: palette.textMuted,
              size: 26,
            ),
            headerPadding: const EdgeInsets.symmetric(
              vertical: Dimens.spacing8,
            ),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle:
                textTheme.labelSmall?.copyWith(color: palette.textMuted) ??
                const TextStyle(),
            weekendStyle:
                textTheme.labelSmall?.copyWith(color: palette.textMuted) ??
                const TextStyle(),
          ),
          focusedDay: widget.focusedDate,
          firstDay: widget.currentDate.subtract(widget.calendarDurationDays),
          lastDay: widget.currentDate.add(widget.calendarDurationDays),
          startingDayOfWeek: StartingDayOfWeek.monday,
          onDaySelected: (selectedDay, focusedDay) {
            if (cycle.enabled &&
                (cycle.recordedOn(selectedDay, DateTime.now()) ||
                    cycle.predictedOn(selectedDay))) {
              showModalBottomSheet<void>(
                context: context,
                useSafeArea: true,
                builder: (sheet) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: Text(S.of(context).diaryLabel),
                        onTap: () {
                          Navigator.pop(sheet);
                          widget.onDateSelected(
                            selectedDay,
                            widget.trackedDaysMap,
                          );
                        },
                      ),
                      ListTile(
                        title: Text(S.of(context).cycleLabel),
                        onTap: () {
                          Navigator.pop(sheet);
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                appBar: AppBar(
                                  title: Text(S.of(context).cycleLabel),
                                ),
                                body: const CyclePage(),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            } else {
              widget.onDateSelected(selectedDay, widget.trackedDaysMap);
            }
          },
          calendarStyle: CalendarStyle(
            markersMaxCount: 1,
            defaultTextStyle:
                textTheme.bodyMedium?.copyWith(color: palette.textStrong) ??
                const TextStyle(),
            weekendTextStyle:
                textTheme.bodyMedium?.copyWith(color: palette.textStrong) ??
                const TextStyle(),
            outsideTextStyle:
                textTheme.bodyMedium?.copyWith(color: palette.textMuted) ??
                const TextStyle(),
            todayTextStyle:
                textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: accent,
                ) ??
                const TextStyle(),
            todayDecoration: BoxDecoration(
              border: Border.all(color: accent, width: 2.0),
              shape: BoxShape.circle,
            ),
            selectedTextStyle:
                textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onPrimary,
                ) ??
                const TextStyle(),
            selectedDecoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
          ),
          selectedDayPredicate: (day) => isSameDay(widget.selectedDate, day),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, date, events) {
              final trackedDay = widget.trackedDaysMap[date.toParsedDay()];
              final recorded =
                  cycle.enabled && cycle.recordedOn(date, DateTime.now());
              final predicted =
                  cycle.enabled &&
                  !recorded &&
                  cycle.predictedOn(date) &&
                  !cycleDate(date).isBefore(cycleDate(DateTime.now()));
              if (recorded || predicted) {
                return Semantics(
                  label: recorded
                      ? S.of(context).cycleRecorded
                      : S.of(context).cyclePredicted,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(top: 10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(
                            0xFF6C8B7E,
                          ).withValues(alpha: recorded ? 1 : 0.18),
                          border: Border.all(color: const Color(0xFF6C8B7E)),
                        ),
                      ),
                      if (trackedDay != null)
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(top: 10, left: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: trackedDay.getCalendarDayRatingColor(
                              context,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }
              if (trackedDay != null) {
                return Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: trackedDay.getCalendarDayRatingColor(context),
                  ),
                  width: 5.0,
                  height: 5.0,
                );
              } else {
                return const SizedBox();
              }
            },
          ),
        ),
      ),
    );
  }
}
