import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_recipe_parser.dart';

import '../../../../fixture/lifesum_export_fixture.dart';

void main() {
  group('LifesumRecipeParser', () {
    test('preserves logged recipe and ingredient snapshot data', () {
      final result = LifesumRecipeParser.parse(
        sanitizedLifesumFiles['recipes.csv']!,
      );

      expect(result.sourceRowCount, 1);
      expect(result.candidates, hasLength(1));
      expect(result.ingredientCount, 1);
      expect(result.issues, isEmpty);
      final recipe = result.candidates.single;
      expect(recipe.title, 'Example bowl');
      expect(recipe.description, isNull);
      expect(recipe.servingsCount, 2);
      expect(recipe.createdAt, DateTime.utc(2024, 1, 2, 12));
      expect(recipe.loggedNutrients.calories, 400);
      expect(recipe.loggedNutrients.carbs, 50);
      expect(recipe.loggedNutrients.potassiumGrams, 0.2);
      expect(recipe.loggedNutrients.sodiumGrams, 0.1);
      expect(recipe.requiresSnapshotPersistence, isTrue);
      expect(recipe.physicalWeightGrams, isNull);

      final ingredient = recipe.ingredients.single;
      expect(ingredient.title, 'Example ingredient');
      expect(ingredient.brand, isNull);
      expect(ingredient.servingName, 'serving');
      expect(ingredient.amount, 1);
      expect(ingredient.physicalWeightGrams, isNull);
      expect(recipe.id, isNot(contains('Example')));
      expect(ingredient.id, isNot(contains('Example')));
    });

    test('groups blank-title continuation rows in source order', () {
      final result = LifesumRecipeParser.parse(
        _csvWithRows(<String>[
          _startRow(title: 'Recipe one', ingredientTitle: 'First item'),
          _continuationRow(ingredientTitle: 'Second item', amount: '2'),
          _startRow(title: 'Recipe two', ingredientTitle: 'Third item'),
        ]),
      );

      expect(result.candidates, hasLength(2));
      expect(result.ingredientCount, 3);
      expect(
        result.candidates.first.ingredients.map((value) => value.title),
        orderedEquals(<String>['First item', 'Second item']),
      );
    });

    test('parses quoted source text without leaking it into IDs', () {
      final result = LifesumRecipeParser.parse(
        _csvWithRows(<String>[
          _startRow(title: 'Recipe, "one"', ingredientTitle: 'Item, chopped'),
        ]),
      );

      final recipe = result.candidates.single;
      expect(recipe.title, 'Recipe, "one"');
      expect(recipe.ingredients.single.title, 'Item, chopped');
      expect(recipe.id, isNot(contains('Recipe')));
      expect(recipe.ingredients.single.id, isNot(contains('chopped')));
    });

    test(
      'preserves exact duplicate recipes and ingredients deterministically',
      () {
        final rows = <String>[
          _startRow(title: 'Repeated recipe', ingredientTitle: 'Repeated item'),
          _continuationRow(
            ingredientTitle: 'Repeated item',
            ingredientBrand: 'Sample brand',
          ),
          _startRow(title: 'Repeated recipe', ingredientTitle: 'Repeated item'),
          _continuationRow(
            ingredientTitle: 'Repeated item',
            ingredientBrand: 'Sample brand',
          ),
        ];

        final first = LifesumRecipeParser.parse(_csvWithRows(rows));
        final second = LifesumRecipeParser.parse(_csvWithRows(rows));

        expect(first.candidates, hasLength(2));
        expect(first.candidates[0].id, endsWith('-001'));
        expect(first.candidates[1].id, endsWith('-002'));
        expect(first.candidates[0].id, second.candidates[0].id);
        expect(first.candidates[0].ingredients, hasLength(2));
        expect(first.candidates[0].ingredients[0].id, endsWith('-001'));
        expect(first.candidates[0].ingredients[1].id, endsWith('-002'));
      },
    );

    test('reports orphan and unexpected continuation data without values', () {
      final orphan = _continuationRow(ingredientTitle: 'Orphan');
      final unexpected = _continuationRow(
        ingredientTitle: 'Second',
        recipeCalories: '5',
      );
      final result = LifesumRecipeParser.parse(
        _csvWithRows(<String>[
          orphan,
          _startRow(title: 'Recipe', ingredientTitle: 'First'),
          unexpected,
        ]),
      );

      expect(result.candidates, hasLength(1));
      expect(result.candidates.single.ingredients, hasLength(2));
      expect(
        result.issues.map((issue) => issue.code),
        containsAll(<LifesumRecipeIssueCode>[
          LifesumRecipeIssueCode.orphanIngredient,
          LifesumRecipeIssueCode.unexpectedContinuationRecipeData,
        ]),
      );
      expect(result.issues.every((issue) => issue.rowNumber != null), isTrue);
    });

    test('skips invalid starts and ingredients with structural warnings', () {
      final result = LifesumRecipeParser.parse(
        _csvWithRows(<String>[
          _startRow(
            title: 'Bad servings',
            servings: '1.5',
            ingredientTitle: 'Item',
          ),
          _startRow(
            title: 'Bad date',
            created: '2024-02-30 12:00:00 +0000 UTC',
            ingredientTitle: 'Item',
          ),
          _startRow(
            title: 'Bad calories',
            calories: 'NaN',
            ingredientTitle: 'Item',
          ),
          _startRow(title: 'Bad ingredient', ingredientTitle: ''),
        ]),
      );

      expect(result.candidates, isEmpty);
      expect(
        result.issues.map((issue) => issue.code),
        containsAll(<LifesumRecipeIssueCode>[
          LifesumRecipeIssueCode.invalidServings,
          LifesumRecipeIssueCode.invalidCreatedAt,
          LifesumRecipeIssueCode.invalidNumber,
          LifesumRecipeIssueCode.missingRequiredValue,
          LifesumRecipeIssueCode.recipeWithoutIngredients,
        ]),
      );
      expect(result.issues.every((issue) => issue.rowNumber != null), isTrue);
    });

    test('missing required headers block the recipe section', () {
      final result = LifesumRecipeParser.parse('title,servings\nExample,2');

      expect(result.candidates, isEmpty);
      expect(result.blockingIssueCount, greaterThan(0));
      expect(result.issues.every((issue) => issue.rowNumber == null), isTrue);
    });
  });
}

String _csvWithRows(List<String> rows) =>
    '${sanitizedLifesumFiles['recipes.csv']!.split('\n').first}\n'
    '${rows.join('\n')}\n';

String _startRow({
  required String title,
  required String ingredientTitle,
  String servings = '2',
  String created = '2024-01-02 12:00:00 +0000 UTC',
  String calories = '400',
}) => _joinCsv(<String>[
  title,
  'Description',
  servings,
  created,
  calories,
  '50',
  '8',
  '4',
  '0',
  '10',
  '2',
  '8',
  '0.2',
  '20',
  '0.1',
  ingredientTitle,
  'Sample brand',
  'serving',
  '1',
]);

String _continuationRow({
  required String ingredientTitle,
  String ingredientBrand = '',
  String amount = '1',
  String recipeCalories = '',
}) => _joinCsv(<String>[
  '',
  '',
  '',
  '',
  recipeCalories,
  '',
  '',
  '',
  '',
  '',
  '',
  '',
  '',
  '',
  '',
  ingredientTitle,
  ingredientBrand,
  'serving',
  amount,
]);

String _joinCsv(List<String> values) => values
    .map((value) {
      if (!value.contains(',') && !value.contains('"')) return value;
      return '"${value.replaceAll('"', '""')}"';
    })
    .join(',');
