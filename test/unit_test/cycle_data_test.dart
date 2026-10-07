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
