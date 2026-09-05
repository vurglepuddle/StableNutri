import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_picker_bounds.dart';

void main() {
  group('profile picker bounds', () {
    test('metric height minimum is clamped to 1', () {
      expect(minSelectableHeight(80, false), 1);
    });

    test('imperial height minimum is clamped to 1', () {
      expect(minSelectableHeight(5, true), 1);
    });

    test('metric height maximum keeps expected range', () {
      expect(maxSelectableHeight(170, false), 270);
    });

    test('weight minimum is clamped to 1 for metric and imperial', () {
      expect(minSelectableWeight(40, false), 1);
      expect(minSelectableWeight(80, true), 1);
    });

    test('weight maximum keeps expected range', () {
      expect(maxSelectableWeight(75, false), 125);
      expect(maxSelectableWeight(140, true), 240);
    });

    test(
      'extreme negative persisted values still produce a valid metric range',
      () {
        expect(
          maxSelectableHeight(-200, false) >= minSelectableHeight(-200, false),
          isTrue,
        );
        expect(
          maxSelectableWeight(-200, false) >= minSelectableWeight(-200, false),
          isTrue,
        );
      },
    );

    test('selected values are clamped to computed minimum', () {
      expect(clampHeightSelection(0.5, 1), 1);
      expect(clampWeightSelection(0.5, 1), 1);
      expect(clampHeightSelection(180, 1), 180);
      expect(clampWeightSelection(80, 1), 80);
    });
  });
}
