import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

// Shared by Diary and Cycle. Keep the week order consistent across the app.
const appCalendarWeekStart = StartingDayOfWeek.monday;

HeaderStyle appCalendarHeader(BuildContext context) => HeaderStyle(
  titleCentered: true,
  formatButtonVisible: false,
  titleTextStyle: Theme.of(
    context,
  ).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600),
  leftChevronIcon: const Icon(Icons.chevron_left_rounded, size: 26),
  rightChevronIcon: const Icon(Icons.chevron_right_rounded, size: 26),
  headerPadding: const EdgeInsets.symmetric(vertical: 8),
);
