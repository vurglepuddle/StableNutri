import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_nutriments_table.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../helpers/test_l10n.dart';

/// Saturated fat, sugar and fibre are often not known — METRO never gives
/// them — and a table saying "0.0g" for them claimed a fact nobody had.
void main() {
  Future<void> pump(WidgetTester tester, MealNutrimentsEntity n) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MealDetailNutrimentsTable(
                product: MealEntity(
                  code: '1',
                  name: 'Бекон',
                  url: null,
                  mealQuantity: '500',
                  mealUnit: 'g',
                  servingQuantity: null,
                  servingUnit: 'g',
                  servingSize: null,
                  nutriments: n,
                  source: MealSourceEntity.fdc,
                ),
                usesImperialUnits: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String label) => find.textContaining(label);

  testWidgets('unknown saturated fat, sugar and fibre are left out', (
    tester,
  ) async {
    await pump(
      tester,
      const MealNutrimentsEntity(
        energyKcal100: 420,
        carbohydrates100: 0,
        fat100: 40,
        proteins100: 16,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
    );

    expect(row(l10nEn.saturatedFatLabel), findsNothing);
    expect(row(l10nEn.sugarLabel), findsNothing);
    expect(row(l10nEn.fiberLabel), findsNothing);
    expect(row(l10nEn.carbohydrateLabel), findsOneWidget);
    expect(find.text('0.0g'), findsOneWidget, reason: 'carbs are known: 0');
  });

  testWidgets('known ones are shown, zero included', (tester) async {
    await pump(
      tester,
      const MealNutrimentsEntity(
        energyKcal100: 420,
        carbohydrates100: 1,
        fat100: 40,
        proteins100: 16,
        sugars100: 0,
        saturatedFat100: 15,
        fiber100: 2,
      ),
    );

    expect(row(l10nEn.saturatedFatLabel), findsOneWidget);
    expect(row(l10nEn.sugarLabel), findsOneWidget);
    expect(row(l10nEn.fiberLabel), findsOneWidget);
  });
}
