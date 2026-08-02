import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/stable_range_calc.dart';

void main() {
  group('StableRangeCalc.classify', () {
    test('classifies below and returns distance to the lower edge', () {
      final result = StableRangeCalc.classify(
        value: 1420,
        lower: 1850,
        upper: 2100,
      );

      expect(result.status, StableRangeStatus.below);
      expect(result.distanceToRange, 430);
    });

    test('treats both boundaries as within the range', () {
      expect(
        StableRangeCalc.classify(value: 1850, lower: 1850, upper: 2100).status,
        StableRangeStatus.within,
      );
      expect(
        StableRangeCalc.classify(value: 2100, lower: 1850, upper: 2100).status,
        StableRangeStatus.within,
      );
    });

    test('classifies above and returns distance from the upper edge', () {
      final result = StableRangeCalc.classify(
        value: 2250,
        lower: 1850,
        upper: 2100,
      );

      expect(result.status, StableRangeStatus.above);
      expect(result.distanceToRange, 150);
    });

    test('supports a legacy zero-width compatibility point', () {
      expect(
        StableRangeCalc.classify(value: 2000, lower: 2000, upper: 2000).status,
        StableRangeStatus.within,
      );
      expect(
        StableRangeCalc.classify(value: 1999, lower: 2000, upper: 2000).status,
        StableRangeStatus.below,
      );
    });

    test('rejects reversed bounds in debug/test builds', () {
      expect(
        () => StableRangeCalc.classify(value: 68, lower: 70, upper: 66),
        throwsAssertionError,
      );
    });
  });

  group('StableRangeCalc.progressTowardUpper', () {
    test('clamps before zero and beyond the upper edge', () {
      expect(StableRangeCalc.progressTowardUpper(value: -1, upper: 2100), 0);
      expect(StableRangeCalc.progressTowardUpper(value: 2200, upper: 2100), 1);
    });

    test('returns proportional progress inside the gauge', () {
      expect(
        StableRangeCalc.progressTowardUpper(value: 1050, upper: 2100),
        0.5,
      );
    });
  });
}
