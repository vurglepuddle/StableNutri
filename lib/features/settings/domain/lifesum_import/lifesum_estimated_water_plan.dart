import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';

/// A preview-only plan for the user's explicitly requested estimated water
/// history. The archive itself contains no water records.
class LifesumEstimatedWaterPlan {
  LifesumEstimatedWaterPlan._({
    required this.startDay,
    required this.endDay,
    required this.amountPerDayMl,
    required this.totalWindowDays,
    required this.existingDayCount,
    required List<WaterIntakeEntity> candidates,
  }) : candidates = List<WaterIntakeEntity>.unmodifiable(candidates);

  /// Estimated history is always opt-in at confirmation time.
  static const selectedByDefault = false;

  /// The candidates are user-provided average history, not archive evidence.
  static const isEstimated = true;

  final DateTime startDay;
  final DateTime endDay;
  final int amountPerDayMl;
  final int totalWindowDays;
  final int existingDayCount;
  final List<WaterIntakeEntity> candidates;

  int get candidateDayCount => candidates.length;

  /// Builds one candidate for each missing logical day in the inclusive
  /// window. Any day already carrying Stable water is kept untouched.
  factory LifesumEstimatedWaterPlan.build({
    required DateTime startDay,
    required DateTime endDay,
    int amountPerDayMl = 2000,
    int dayStartOffsetMinutes = 0,
    Iterable<WaterIntakeEntity> existingEntries = const <WaterIntakeEntity>[],
  }) {
    final normalizedStart = DateTime(
      startDay.year,
      startDay.month,
      startDay.day,
    );
    final normalizedEnd = DateTime(endDay.year, endDay.month, endDay.day);
    if (normalizedEnd.isBefore(normalizedStart)) {
      throw ArgumentError.value(endDay, 'endDay', 'must not precede startDay');
    }
    if (amountPerDayMl <= 0) {
      throw ArgumentError.value(
        amountPerDayMl,
        'amountPerDayMl',
        'must be positive',
      );
    }
    final offsetMinutes =
        dayStartOffsetMinutes >= 0 && dayStartOffsetMinutes < 24 * 60
        ? dayStartOffsetMinutes
        : 0;
    final existingDayKeys = existingEntries
        .map(
          (entry) => _dayKey(
            DayBoundaryCalc.logicalDayOfMinutes(entry.dateTime, offsetMinutes),
          ),
        )
        .toSet();
    final candidates = <WaterIntakeEntity>[];
    var existingDayCount = 0;
    var totalWindowDays = 0;
    for (
      var day = normalizedStart;
      !day.isAfter(normalizedEnd);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      totalWindowDays++;
      if (existingDayKeys.contains(_dayKey(day))) {
        existingDayCount++;
        continue;
      }
      candidates.add(
        WaterIntakeEntity(
          id: 'lifesum-estimated-water-${_dateSlug(day)}-$amountPerDayMl',
          dateTime: day.add(Duration(minutes: offsetMinutes + 12 * 60)),
          amountMl: amountPerDayMl,
        ),
      );
    }
    return LifesumEstimatedWaterPlan._(
      startDay: normalizedStart,
      endDay: normalizedEnd,
      amountPerDayMl: amountPerDayMl,
      totalWindowDays: totalWindowDays,
      existingDayCount: existingDayCount,
      candidates: candidates,
    );
  }

  static int _dayKey(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  static String _dateSlug(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
}
