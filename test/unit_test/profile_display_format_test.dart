import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_display_format.dart';

void main() {
  group('formatProfileWeight', () {
    test('shows whole numbers without decimal suffix', () {
      expect(formatProfileWeight(80.0), '80');
    });

    test('preserves one decimal place for fractional values', () {
      expect(formatProfileWeight(80.5), '80.5');
    });

    test('normalizes floating-point noise around whole values', () {
      expect(formatProfileWeight(154.0000001), '154');
    });

    test('rounds values to one decimal place', () {
      expect(formatProfileWeight(154.25), '154.3');
    });
  });

  group('formatBodyWeightRange', () {
    test('shares the suffix for kilograms', () {
      expect(
        formatBodyWeightRange(
          70,
          75.5,
          BodyWeightUnit.kg,
          kgLabel: 'kg',
          lbLabel: 'lb',
          stLabel: 'st',
        ),
        '70–75.5 kg',
      );
    });

    test('converts both bounds for pounds', () {
      expect(
        formatBodyWeightRange(
          70,
          75,
          BodyWeightUnit.lb,
          kgLabel: 'kg',
          lbLabel: 'lb',
          stLabel: 'st',
        ),
        '154.3–165.3 lb',
      );
    });

    test('keeps compound stone units on both bounds', () {
      expect(
        formatBodyWeightRange(
          70,
          75,
          BodyWeightUnit.st,
          kgLabel: 'kg',
          lbLabel: 'lb',
          stLabel: 'st',
        ),
        '11 st 0.3 lb–11 st 11.3 lb',
      );
    });
  });
}
