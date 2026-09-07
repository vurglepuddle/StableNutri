import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/macro_split_dialog.dart';

/// The macro split has to persist as three integers summing to exactly 100.
///
/// `SettingsBloc.setMacroGoals` stores each share via `toInt() / 100`, which
/// truncates. `_redistribute` in the dialog splits the moved delta across the
/// other two shares by ratio, so it routinely leaves fractions — nudging
/// carbs from 60 to 61 leaves protein at 14.625 and fat at 24.375. Passing
/// those raw truncated the split to 61 + 14 + 24 = 99%, while the dialog's
/// own "% total" line rounded them and displayed 100%.
void main() {
  int sum((int, int, int) t) => t.$1 + t.$2 + t.$3;

  group('roundMacroPercentsToHundred', () {
    test('the one-notch nudge that used to persist 99%', () {
      // carbs 60 -> 61, redistributed by ratio across 15 and 25.
      const carbs = 61.0, protein = 14.625, fat = 24.375;

      // The old save path, reproduced here so the defect is pinned
      // independently of the code that fixes it: setMacroGoals truncates.
      final truncated = carbs.toInt() + protein.toInt() + fat.toInt();
      expect(truncated, 99, reason: 'the bug this function exists to prevent');

      // And the dialog's own "% total" line rounds, so it read 100 while
      // 99 was being written.
      final displayed = carbs.round() + protein.round() + fat.round();
      expect(displayed, 100);

      final result = roundMacroPercentsToHundred(carbs, protein, fat);

      expect(sum(result), 100);
      expect(result, (61, 15, 24));
    });

    test('an already-integral split is left alone', () {
      expect(roundMacroPercentsToHundred(60, 15, 25), (60, 15, 25));
      expect(roundMacroPercentsToHundred(50, 30, 20), (50, 30, 20));
    });

    test('two half-up remainders do not produce 101', () {
      // 33.5 + 33.5 + 33 rounds independently to 34 + 34 + 33 = 101.
      final result = roundMacroPercentsToHundred(33.5, 33.5, 33);

      expect(sum(result), 100);
    });

    test('three equal thirds still sum to 100', () {
      final result = roundMacroPercentsToHundred(100 / 3, 100 / 3, 100 / 3);

      expect(sum(result), 100);
      // Largest-remainder with equal remainders falls back to index order.
      expect(result, (34, 33, 33));
    });

    test('shares that do not total 100 are scaled before rounding', () {
      // The dialog can leave a total slightly off; the persisted triple must
      // still be a valid split rather than a faithful copy of a bad one.
      final result = roundMacroPercentsToHundred(30, 15, 5);

      expect(sum(result), 100);
      expect(result.$1, greaterThan(result.$2));
    });

    test('a degenerate all-zero split falls back to the defaults', () {
      expect(roundMacroPercentsToHundred(0, 0, 0), (60, 15, 25));
    });

    test('every one-notch slider position round-trips to exactly 100', () {
      // Sweep the moved share across the dialog's own 5..90 bounds, splitting
      // the remainder by the default 15:25 ratio the way _redistribute does.
      for (var carbs = 5; carbs <= 90; carbs++) {
        final rest = 100 - carbs;
        final result = roundMacroPercentsToHundred(
          carbs.toDouble(),
          rest * 15 / 40,
          rest * 25 / 40,
        );

        expect(
          sum(result),
          100,
          reason: 'carbs at $carbs% persisted as ${sum(result)}%',
        );
      }
    });
  });
}
