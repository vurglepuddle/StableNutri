import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_calendar_style.dart';
import 'package:opennutritracker/features/cycle/domain/cycle_data.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:table_calendar/table_calendar.dart';

/// The same quiet date ring in Diary, Cycle and period entry.
class CycleDateRing extends StatelessWidget {
  final bool predicted;
  const CycleDateRing({super.key, this.predicted = false});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? const Color(0xFFA8C4B7) : const Color(0xFF6C8B7E);
    return IgnorePointer(
      child: Semantics(
        label: predicted
            ? S.of(context).cyclePredicted
            : S.of(context).cycleRecorded,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: predicted
              ? CustomPaint(
                  painter: _DottedRingPainter(color.withValues(alpha: 0.6)),
                  child: const SizedBox.expand(),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.06),
                    border: Border.all(
                      color: color.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Evenly spaced dots, so an estimate never reads as a recorded day.
class _DottedRingPainter extends CustomPainter {
  final Color color;
  const _DottedRingPainter(this.color);

  static const _dotRadius = 1.1;
  static const _spacing = 4.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - _dotRadius;
    if (radius <= 0) return;
    final count = (2 * math.pi * radius / _spacing).round().clamp(8, 64);
    final paint = Paint()..color = color;
    for (var i = 0; i < count; i++) {
      final angle = 2 * math.pi * i / count - math.pi / 2;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        _dotRadius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DottedRingPainter old) => old.color != color;
}

class CycleCalendarLegend extends StatelessWidget {
  final bool showPrediction;
  const CycleCalendarLegend({super.key, this.showPrediction = true});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 8,
    children: [
      for (final predicted in [false, if (showPrediction) true])
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CycleDateRing(predicted: predicted),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                predicted
                    ? S.of(context).cyclePredicted
                    : S.of(context).cycleRecorded,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
    ],
  );
}

class CycleCalendar extends StatefulWidget {
  final CycleData data;
  final DateTime initialDay;
  final DateTime firstDay;
  final DateTime lastDay;
  final DateTime? start;
  final DateTime? end;
  final bool range;
  final bool showPrediction;
  final void Function(DateTime start, DateTime? end)? onSelected;

  const CycleCalendar({
    super.key,
    required this.data,
    required this.initialDay,
    required this.firstDay,
    required this.lastDay,
    this.start,
    this.end,
    this.range = false,
    this.showPrediction = true,
    this.onSelected,
  });

  @override
  State<CycleCalendar> createState() => _CycleCalendarState();
}

class _CycleCalendarState extends State<CycleCalendar> {
  late DateTime focused = widget.initialDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final text = theme.textTheme.bodyMedium!;
    final selected = BoxDecoration(color: accent, shape: BoxShape.circle);
    // Seven columns are a spatial control; surrounding labels keep full scaling.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: TableCalendar<void>(
        locale: Localizations.localeOf(context).toString(),
        startingDayOfWeek: appCalendarWeekStart,
        firstDay: widget.firstDay,
        lastDay: widget.lastDay,
        focusedDay: focused,
        headerStyle: appCalendarHeader(context),
        daysOfWeekHeight: 26,
        rowHeight: 48,
        availableGestures: AvailableGestures.horizontalSwipe,
        onPageChanged: (day) => focused = day,
        // Selection is controlled by the parent, including a one-day range.
        // TableCalendar's built-in range gesture ignores a second tap on the
        // same date and keeps a separate pending start across mode changes.
        rangeSelectionMode: RangeSelectionMode.disabled,
        rangeStartDay: widget.range ? widget.start : null,
        rangeEndDay: widget.range ? widget.end : null,
        selectedDayPredicate: (day) =>
            !widget.range && isSameDay(day, widget.start),
        onDaySelected: widget.onSelected == null
            ? null
            : (day, focus) {
                setState(() => focused = focus);
                final selected = cycleDate(day);
                final start = widget.start;
                if (!widget.range || start == null || widget.end != null) {
                  widget.onSelected!(selected, null);
                } else if (selected.isBefore(start)) {
                  widget.onSelected!(selected, start);
                } else {
                  widget.onSelected!(start, selected);
                }
              },
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: theme.textTheme.labelSmall!,
          weekendStyle: theme.textTheme.labelSmall!,
        ),
        calendarStyle: CalendarStyle(
          cellMargin: const EdgeInsets.all(5),
          defaultTextStyle: text,
          weekendTextStyle: text,
          outsideTextStyle: text.copyWith(color: theme.disabledColor),
          todayTextStyle: text.copyWith(
            color: accent,
            fontWeight: FontWeight.w600,
          ),
          todayDecoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: accent),
          ),
          selectedDecoration: selected,
          rangeStartDecoration: selected,
          rangeEndDecoration: selected,
          selectedTextStyle: text.copyWith(color: theme.colorScheme.onPrimary),
          rangeStartTextStyle: text.copyWith(
            color: theme.colorScheme.onPrimary,
          ),
          rangeEndTextStyle: text.copyWith(color: theme.colorScheme.onPrimary),
          withinRangeTextStyle: text,
          rangeHighlightColor: accent.withValues(alpha: 0.12),
        ),
        calendarBuilders: CalendarBuilders(
          markerBuilder: (context, day, _) {
            final recorded = widget.data.recordedOn(day, DateTime.now());
            final predicted =
                widget.showPrediction &&
                !recorded &&
                !cycleDate(day).isBefore(cycleDate(DateTime.now())) &&
                widget.data.predictedOn(day);
            if (!recorded && !predicted) return null;
            return Positioned.fill(child: CycleDateRing(predicted: predicted));
          },
        ),
      ),
    );
  }
}
