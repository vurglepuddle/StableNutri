import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_estimated_water_plan.dart';

void main() {
  group('LifesumEstimatedWaterPlan', () {
    test('builds the requested inclusive 2000 ml history as default-off', () {
      final plan = LifesumEstimatedWaterPlan.build(
        startDay: DateTime(2022, 2, 10),
        endDay: DateTime(2026, 8, 30),
      );

      expect(LifesumEstimatedWaterPlan.selectedByDefault, isFalse);
      expect(LifesumEstimatedWaterPlan.isEstimated, isTrue);
      expect(plan.amountPerDayMl, 2000);
      expect(plan.totalWindowDays, 1663);
      expect(plan.candidateDayCount, 1663);
      expect(plan.existingDayCount, 0);
      expect(plan.candidates.first.amountMl, 2000);
      expect(plan.candidates.first.id, 'lifesum-estimated-water-20220210-2000');
      expect(plan.candidates.last.id, 'lifesum-estimated-water-20260830-2000');
    });

    test('keeps days with existing Stable water untouched', () {
      final plan = LifesumEstimatedWaterPlan.build(
        startDay: DateTime(2024, 1, 1),
        endDay: DateTime(2024, 1, 3),
        existingEntries: <WaterIntakeEntity>[
          WaterIntakeEntity(
            id: 'existing-one',
            dateTime: DateTime(2024, 1, 2, 10),
            amountMl: 250,
          ),
          WaterIntakeEntity(
            id: 'existing-two',
            dateTime: DateTime(2024, 1, 2, 12),
            amountMl: 500,
          ),
        ],
      );

      expect(plan.totalWindowDays, 3);
      expect(plan.existingDayCount, 1);
      expect(plan.candidateDayCount, 2);
      expect(
        plan.candidates.map((entry) => entry.dateTime.day),
        orderedEquals(<int>[1, 3]),
      );
    });

    test('uses logical-day matching and midpoint timestamps', () {
      const offset = 4 * 60 + 30;
      final plan = LifesumEstimatedWaterPlan.build(
        startDay: DateTime(2024, 1, 1),
        endDay: DateTime(2024, 1, 2),
        dayStartOffsetMinutes: offset,
        existingEntries: <WaterIntakeEntity>[
          WaterIntakeEntity(
            id: 'late-night-entry',
            dateTime: DateTime(2024, 1, 2, 2),
            amountMl: 250,
          ),
        ],
      );

      expect(plan.existingDayCount, 1);
      expect(plan.candidates, hasLength(1));
      final candidate = plan.candidates.single;
      expect(candidate.dateTime, DateTime(2024, 1, 2, 16, 30));
      expect(
        DayBoundaryCalc.logicalDayOfMinutes(candidate.dateTime, offset),
        DateTime(2024, 1, 2),
      );
    });

    test('rejects reversed windows and non-positive estimates', () {
      expect(
        () => LifesumEstimatedWaterPlan.build(
          startDay: DateTime(2024, 1, 2),
          endDay: DateTime(2024, 1, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => LifesumEstimatedWaterPlan.build(
          startDay: DateTime(2024, 1, 1),
          endDay: DateTime(2024, 1, 2),
          amountPerDayMl: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
