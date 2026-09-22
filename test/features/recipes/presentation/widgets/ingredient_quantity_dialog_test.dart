import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/ingredient_quantity_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

MealEntity _solidMeal({String unit = 'g'}) => MealEntity(
  code: 'flour',
  name: 'Flour',
  url: null,
  mealQuantity: null,
  mealUnit: unit,
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
  nutriments: MealNutrimentsEntity.empty(),
  source: MealSourceEntity.off,
);

Widget _wrap({required Widget child}) {
  return MaterialApp(
    localizationsDelegates: const [S.delegate],
    supportedLocales: S.supportedLocales,
    home: child,
  );
}

void main() {
  for (final entry in [
    (saved: 'g', mealUnit: 'ml', expected: 'ml', amount: 2.0),
    (saved: 'fl oz', mealUnit: 'ml', expected: 'fl.oz', amount: 2.0),
    (saved: 'cl', mealUnit: 'ml', expected: 'ml', amount: 20.0),
    (saved: 'missing', mealUnit: 'g', expected: 'g', amount: null),
    (saved: 'serving', mealUnit: 'g', expected: 'g', amount: null),
  ]) {
    testWidgets(
      'saved ${entry.saved} on ${entry.mealUnit} opens and submits safely',
      (tester) async {
        IngredientQuantitySelection? captured;
        await tester.pumpWidget(
          _wrap(
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Open'),
                  onPressed: () async {
                    captured = await showIngredientQuantityDialog(
                      context,
                      meal: _solidMeal(unit: entry.mealUnit),
                      initialAmount: 2,
                      initialUnit: entry.saved,
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final field = tester.widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        );
        expect(field.initialValue, entry.expected);
        expect(
          tester
              .widget<DropdownButton<String>>(
                find.byType(DropdownButton<String>),
              )
              .items!
              .where((item) => item.value == entry.expected),
          hasLength(1),
        );
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();
        if (entry.amount == null) {
          expect(captured, isNull);
        } else {
          expect(captured!.unit, entry.expected);
          expect(captured!.amount, entry.amount);
        }
      },
    );
  }

  testWidgets('returns selection on confirm', (tester) async {
    IngredientQuantitySelection? captured;

    await tester.pumpWidget(
      _wrap(
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showIngredientQuantityDialog(
                    context,
                    meal: _solidMeal(),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Default amount is 0; type 150 and confirm with the Add button.
    await tester.enterText(find.byType(TextFormField).first, '150');
    // The confirm button label is the localized addLabel ("Add").
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.amount, 150);
    // Default unit for a solid meal without serving values is 'g'.
    expect(captured!.unit, 'g');
  });

  testWidgets('returns null when amount is invalid', (tester) async {
    IngredientQuantitySelection? captured = const IngredientQuantitySelection(
      amount: -1,
      unit: 'sentinel',
    );

    await tester.pumpWidget(
      _wrap(
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showIngredientQuantityDialog(
                    context,
                    meal: _solidMeal(),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Don't enter anything; just tap Add.
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(captured, isNull);
  });
}
