import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/util/food_emoji_resolver.dart';

void main() {
  group('resolveFoodEmoji — null / empty', () {
    test('null name → null', () {
      expect(resolveFoodEmoji(null), isNull);
    });

    test('empty name → null', () {
      expect(resolveFoodEmoji(''), isNull);
    });

    test('whitespace-only name → null', () {
      expect(resolveFoodEmoji('   '), isNull);
    });

    test('leading comma → null', () {
      // split(',').first is empty after trim.
      expect(resolveFoodEmoji(', whatever'), isNull);
    });
  });

  group('resolveFoodEmoji — direct lookup', () {
    test('single-word head matches', () {
      expect(resolveFoodEmoji('milk'), '🥛');
    });

    test('multi-word head matches', () {
      expect(resolveFoodEmoji('sweet potato'), '🍠');
    });

    test('case-insensitive', () {
      expect(resolveFoodEmoji('MILK'), '🥛');
      expect(resolveFoodEmoji('Olive Oil'), '🫒');
    });

    test('USDA comma-separated description: first token is the head', () {
      expect(
        resolveFoodEmoji(
          'Milk, fluid, nonfat, calcium fortified (fat free or skim)',
        ),
        '🥛',
      );
      expect(resolveFoodEmoji('Apples, raw, fuji, with skin'), '🍎');
    });

    test('leading/trailing whitespace is trimmed', () {
      expect(resolveFoodEmoji('  apple  '), '🍎');
    });
  });

  group('resolveFoodEmoji — auto-generated variants', () {
    test('regular +s plural is generated from the singular', () {
      // 'eggs' / 'apples' aren't listed; auto-generated from 'egg' / 'apple'.
      expect(resolveFoodEmoji('eggs'), '🥚');
      expect(resolveFoodEmoji('apples'), '🍎');
    });

    test('multi-word noun also matches without internal spaces', () {
      // 'olive oil' is listed; 'oliveoil' and 'oliveoils' are auto-gen.
      expect(resolveFoodEmoji('olive oil'), '🫒');
      expect(resolveFoodEmoji('olive oils'), '🫒');
      expect(resolveFoodEmoji('oliveoil'), '🫒');
      expect(resolveFoodEmoji('oliveoils'), '🫒');
    });

    test('irregular plurals must be listed explicitly', () {
      // -ies, -oes, etc. don't reduce from the singular by +s, so they need
      // to be in the map verbatim. These regress if someone removes them.
      expect(resolveFoodEmoji('cherries'), '🍒');
      expect(resolveFoodEmoji('strawberries'), '🍓');
      expect(resolveFoodEmoji('potatoes'), '🥔');
      expect(resolveFoodEmoji('tomatoes'), '🍅');
      expect(resolveFoodEmoji('fungi'), '🍄');
    });
  });

  group('resolveFoodEmoji — no false positives', () {
    test('unknown noun returns null (no fallback fabrication)', () {
      // 'seaweed' is intentionally omitted — no good emoji.
      expect(resolveFoodEmoji('seaweed'), isNull);
    });

    test("'s'-ending non-plural that isn't in the map returns null", () {
      // 'bass' isn't listed (only 'sea bass' is). The resolver no longer
      // strips trailing 's' from the input, so 'bass' must not match
      // anything in the map — guards against future map additions that
      // might accidentally introduce a 'bas' key.
      expect(resolveFoodEmoji('bass'), isNull);
    });

    test('one-character input does not throw', () {
      expect(() => resolveFoodEmoji('s'), returnsNormally);
      expect(resolveFoodEmoji('s'), isNull);
    });
  });

  group('resolveFoodEmoji — anti-regressions', () {
    // Adjacent string literals in Dart get silently concatenated. A missing
    // comma between two list entries collapses them into a single garbled
    // string, breaking both. These spot-checks would have caught that.
    test('yoghurt (UK spelling) and ice cream both resolve', () {
      expect(resolveFoodEmoji('yoghurt'), '🍦');
      expect(resolveFoodEmoji('ice cream'), '🍦');
    });

    test('greens (explicit map entry, no singular) resolves', () {
      // 'greens' is listed verbatim — there's no singular 'green' in the
      // map. With the new approach the input isn't manipulated, so we'd
      // miss this if 'greens' got removed.
      expect(resolveFoodEmoji('greens'), '🥬');
    });
  });
}
