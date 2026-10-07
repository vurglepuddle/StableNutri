import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/cycle/domain/cycle_data.dart';

void main() {
  PeriodRecord row(String id, int day, {int? end, bool gap = false}) =>
      PeriodRecord(
        id: id,
        start: DateTime(2026, 1, day),
        end: end == null ? null : DateTime(2026, 1, end),
        gapBefore: gap,
      );

  test('uses setup estimates without fabricating observations', () {
    final data = CycleData(guessedStart: DateTime(2026, 1, 1));
    expect(data.expectedStart, DateTime(2026, 1, 29));
    expect(data.cycleLengths, isEmpty);
    expect(data.periodLengths, isEmpty);
    expect(data.records, isEmpty);
  });
  test(
    'observed starts and inclusive ends replace each estimate independently',
    () {
      final data = CycleData(
        records: [row('a', 1, end: 5), row('b', 31, end: 34), row('c', 59)],
      );
      data.validate();
      expect(data.averageCycle, 29);
      expect(data.averagePeriod, 4.5);
      expect(data.expectedStart, DateTime(2026, 1, 88));
      expect(data.periodLengths.length, 2);
    },
  );
  test('only six recent complete observations inform each average', () {
    final data = CycleData(
      records: [
        for (var i = 0; i < 9; i++) row('$i', 1 + i * 30, end: 5 + i * 30),
      ],
    );
    expect(data.averageCycle, 30);
    expect(data.averagePeriod, 5);
    final gap = data.copyWith(
      records: [row('a', 1, end: 5), row('b', 61, end: 65, gap: true)],
    );
    expect(gap.cycleLengths, isEmpty);
    expect(gap.records.length, 2);
  });
  test('forecasts repeat every cycle without drifting', () {
    // Intervals 29, 30, 29, 30, 29: the average is 29.4 days.
    final data = CycleData(
      records: [
        for (final (i, day) in [0, 29, 59, 88, 118, 147].indexed)
          PeriodRecord(
            id: '$i',
            start: DateTime(2026, 1, 1 + day),
            end: DateTime(2026, 1, 5 + day),
          ),
      ],
    );
    final last = DateTime(2026, 1, 148);
    bool on(int offset) =>
        data.predictedOn(DateTime(last.year, last.month, last.day + offset));
    expect(data.averageCycle, closeTo(29.4, 1e-9));
    expect(data.expectedStart, DateTime(2026, 1, 148 + 29));
    // Cycle 1 starts at 29, cycle 10 at round(294) = 294, never 290.
    for (final n in [1, 2, 6, 10, 20]) {
      final start = (n * 29.4).round();
      expect(on(start - 1), isFalse, reason: 'day before cycle $n');
      expect(on(start), isTrue, reason: 'start of cycle $n');
      expect(on(start + 4), isTrue, reason: 'last day of cycle $n');
      expect(on(start + 5), isFalse, reason: 'day after cycle $n');
    }
    expect(on(0), isFalse, reason: 'the recorded start is not a forecast');
    expect(on(-29), isFalse);
  });
  test('a moved forecast anchors the cycles after it', () {
    final data = CycleData(
      records: [row('a', 1, end: 5)],
      expectedOverride: DateTime(2026, 2, 3),
    );
    expect(data.predictedOn(DateTime(2026, 2, 3)), isTrue);
    expect(data.predictedOn(DateTime(2026, 1, 29)), isFalse);
    expect(data.predictedOn(DateTime(2026, 3, 3)), isTrue);
    expect(data.predictedOn(DateTime(2026, 3, 2)), isFalse);
  });
  test('moving a forecast never becomes a recorded start', () {
    final data = CycleData(records: [row('a', 1, end: 5)]);
    final moved = data.copyWith(expectedOverride: DateTime(2026, 2, 3));
    expect(moved.expectedStart, DateTime(2026, 2, 3));
    expect(moved.cycleLengths, isEmpty);
    expect(moved.records, data.records);
    expect(
      moved.copyWith(clearExpected: true).expectedStart,
      DateTime(2026, 1, 29),
    );
  });
  test(
    'rejects overlaps, open periods before another start and invalid dates',
    () {
      expect(
        () => CycleData(
          records: [row('a', 1, end: 5), row('b', 5, end: 7)],
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => CycleData(records: [row('a', 1), row('b', 31)]).validate(),
        throwsFormatException,
      );
      expect(
        () => CycleData(records: [row('a', 5, end: 1)]).validate(),
        throwsFormatException,
      );
      expect(
        () => CycleData(
          records: [row('a', 5)],
        ).validate(today: DateTime(2026, 1, 1)),
        throwsFormatException,
      );
    },
  );
  test('calendar arithmetic and serialization preserve dates and opt-ins', () {
    expect(cycleDays(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
    final data = CycleData(
      enabled: true,
      reminderEnabled: true,
      reminderHour: 14,
      records: [row('a', 1, end: 5)],
    );
    final restored = CycleData.decode(data.encode());
    expect(restored.encode(), data.encode());
    expect(
      restored.recordedOn(DateTime(2026, 1, 5), DateTime(2026, 2, 1)),
      isTrue,
    );
    expect(restored.predictedOn(DateTime(2026, 1, 29)), isTrue);
  });
}
