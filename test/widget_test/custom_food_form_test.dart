import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../helpers/test_l10n.dart';

class _Config extends Fake implements ConfigEntity {
  @override
  bool get usesImperialFoodUnits => false;
}

class _GetConfig extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => _Config();
}

class _Saved extends Fake implements CustomMealDataSource {
  final meals = <MealDBO>[];
  @override
  Future<void> saveCustomMeal(MealDBO meal) async => meals.add(meal);
}

/// The food form: name, brand and barcode; then one serving in g or ml;
/// then nutrition per 100 g, or per serving when that is what is known.
void main() {
  late _Saved saved;
  MealEntity? result;

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  Future<void> pumpForm(
    WidgetTester tester, {
    MealEntity? meal,
    Size size = const Size(411, 1400),
    double textScale = 1,
    bool newFood = false,
    String? prefilledFrom,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    saved = _Saved();
    result = null;
    final bloc = EditMealBloc(_GetConfig(), saved);
    final energy = EnergyUnitProvider();
    locator.registerFactory<EditMealBloc>(() => bloc);
    addTearDown(() async {
      await locator.reset();
      await bloc.close();
      energy.dispose();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: energy,
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<MealEntity>(
                  MaterialPageRoute(
                    settings: RouteSettings(
                      arguments: EditMealScreenArguments(
                        DateTime(2026, 9, 25),
                        meal ?? MealEntity.empty(),
                        IntakeTypeEntity.lunch,
                        false,
                        editOnly: true,
                        newFood: newFood,
                        prefilledFrom: prefilledFrom,
                      ),
                    ),
                    builder: (_) => const EditMealScreen(),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text(l10nEn.buttonSaveLabel));
    await tester.pumpAndSettle();
  }

  testWidgets('a new food saves its serving and per-100 values', (
    tester,
  ) async {
    await pumpForm(tester);
    expect(find.text(l10nEn.customFoodNewTitle), findsOneWidget);

    await tester.enterText(field(l10nEn.mealNameLabel), 'Soup');
    await tester.enterText(field(l10nEn.customFoodServingSizeLabel), '300');
    await tester.enterText(
      field('${l10nEn.mealEnergyLabel} (${l10nEn.kcalLabel})'),
      '50',
    );
    await tester.enterText(field(l10nEn.mealCarbsLabel), '6');
    await tester.enterText(field(l10nEn.mealFatLabel), '2');
    await tester.enterText(field(l10nEn.mealProteinLabel), '2');
    await save(tester);

    final meal = result!;
    expect(meal.name, 'Soup');
    expect(meal.mealUnit, 'g');
    expect(meal.servingQuantity, 300);
    expect(meal.servingUnit, 'g');
    expect(meal.nutriments.energyKcal100, 50);
    expect(meal.nutriments.carbohydrates100, 6);
    expect(saved.meals.single.servingQuantity, 300);
  });

  testWidgets('values typed per serving are stored per 100 g', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field(l10nEn.mealNameLabel), 'Soup bowl');
    await tester.enterText(field(l10nEn.customFoodServingSizeLabel), '200');
    final kcal = field('${l10nEn.mealEnergyLabel} (${l10nEn.kcalLabel})');
    await tester.enterText(kcal, '50');
    await tester.enterText(field(l10nEn.mealCarbsLabel), '6');
    await tester.enterText(field(l10nEn.mealFatLabel), '2');
    await tester.enterText(field(l10nEn.mealProteinLabel), '2');

    // Switching keeps the meaning: 50 kcal per 100 g is 100 per 200 g.
    await tester.tap(find.text(l10nEn.customFoodPerServing));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(kcal).controller!.text, '100');

    await tester.enterText(kcal, '120');
    await tester.enterText(field(l10nEn.mealCarbsLabel), '15');
    await tester.enterText(field(l10nEn.mealFatLabel), '4');
    await tester.enterText(field(l10nEn.mealProteinLabel), '6');
    await save(tester);

    expect(result!.nutriments.energyKcal100, 60);
    expect(result!.nutriments.carbohydrates100, 7.5);
  });

  testWidgets('per serving waits for a serving size', (tester) async {
    await pumpForm(tester);
    SegmentedButton<dynamic> basis() => tester.widget<SegmentedButton<dynamic>>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SegmentedButton &&
            widget.segments.any(
              (segment) =>
                  (segment.label as Text?)?.data == l10nEn.customFoodPerServing,
            ),
      ),
    );
    expect(basis().segments.last.enabled, isFalse);
    await tester.enterText(field(l10nEn.customFoodServingSizeLabel), '30');
    await tester.pump();
    expect(basis().segments.last.enabled, isTrue);
  });

  testWidgets('blank macros are none, so the food can be logged', (
    tester,
  ) async {
    await pumpForm(tester);
    await tester.enterText(field(l10nEn.mealNameLabel), 'Olive oil');
    await tester.enterText(
      field('${l10nEn.mealEnergyLabel} (${l10nEn.kcalLabel})'),
      '884',
    );
    await tester.enterText(field(l10nEn.mealFatLabel), '100');
    await save(tester);

    expect(result!.nutriments.carbohydrates100, 0);
    expect(result!.nutriments.proteins100, 0);
    expect(result!.scalableServingQuantity, isNull);
  });

  testWidgets('more grams than the food weighs are refused', (tester) async {
    await pumpForm(tester);
    await tester.enterText(field(l10nEn.mealNameLabel), 'Typo');
    await tester.enterText(field(l10nEn.mealCarbsLabel), '150');
    await save(tester);

    expect(result, isNull);
    expect(
      find.text(l10nEn.customFoodNutrientTooHigh(l10nEn.mealCarbsLabel)),
      findsOneWidget,
    );
  });

  testWidgets('renaming a food leaves its numbers exactly as they were', (
    tester,
  ) async {
    final meal = MealEntity(
      code: 'lifesum-meal-1',
      name: 'Pizza slice',
      url: null,
      mealQuantity: null,
      mealUnit: 'serving',
      servingQuantity: 1,
      servingUnit: 'serving',
      servingSize: 'slice',
      nutriments: const MealNutrimentsEntity(
        energyKcal100: 28533.333333,
        carbohydrates100: 3000.123,
        fat100: 1000,
        proteins100: 1000,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceEntity.custom,
    );
    await pumpForm(tester, meal: meal);
    // Counted in servings: shown per serving, with no weight to pick.
    expect(find.text(l10nEn.customFoodCountedInServings), findsOneWidget);
    expect(field(l10nEn.customFoodServingSizeLabel), findsNothing);
    expect(
      tester
          .widget<TextField>(
            field('${l10nEn.mealEnergyLabel} (${l10nEn.kcalLabel})'),
          )
          .controller!
          .text,
      '285.33',
    );

    await tester.enterText(field(l10nEn.mealNameLabel), 'Pizza');
    await save(tester);

    expect(result!.name, 'Pizza');
    expect(result!.nutriments.energyKcal100, closeTo(28533.333333, 1e-6));
    expect(result!.nutriments.carbohydrates100, closeTo(3000.123, 1e-6));
    expect(result!.mealUnit, 'serving');
  });

  testWidgets('the form fits a 320 px phone at 1.6x text', (tester) async {
    await pumpForm(tester, size: const Size(320, 700), textScale: 1.6);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('pre-filled from a found product', () {
    MealEntity found() => MealEntity(
      code: '4601751024794',
      name: 'Сыр Natura Сливочный 45%, 150г',
      brands: 'Natura',
      url: 'https://online.metro-cc.ru/products/x',
      mealQuantity: '150',
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: '',
      nutriments: const MealNutrimentsEntity(
        energyKcal100: 340,
        carbohydrates100: 0,
        fat100: null,
        proteins100: 25,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceEntity.custom,
    );

    Finder helper(String label, String text) =>
        find.descendant(of: field(label), matching: find.text(text));

    testWidgets('says where it came from and stays a new food', (tester) async {
      await pumpForm(
        tester,
        meal: found(),
        newFood: true,
        prefilledFrom: 'METRO',
      );

      expect(find.text(l10nEn.customFoodNewTitle), findsOneWidget);
      expect(
        find.text(l10nEn.customFoodPrefilledNote('METRO')),
        findsOneWidget,
      );
      expect(find.text('Сыр Natura Сливочный 45%, 150г'), findsOneWidget);
    });

    testWidgets('highlights the missing main value until it is typed', (
      tester,
    ) async {
      await pumpForm(
        tester,
        meal: found(),
        newFood: true,
        prefilledFrom: 'METRO',
      );
      final missing = l10nEn.customFoodMissingValue;

      expect(helper(l10nEn.mealFatLabel, missing), findsOneWidget);
      expect(helper(l10nEn.mealProteinLabel, missing), findsNothing);
      expect(
        helper(l10nEn.mealCarbsLabel, missing),
        findsNothing,
        reason: 'zero is a value, not a gap',
      );

      await tester.enterText(field(l10nEn.mealFatLabel), '26');
      await tester.pump();
      expect(find.text(missing), findsNothing);

      await save(tester);
      expect(result!.code, '4601751024794');
      expect(result!.nutriments.fat100, 26);
      expect(result!.nutriments.proteins100, 25);
      expect(saved.meals.single.code, '4601751024794');
    });

    testWidgets('a blank form highlights nothing', (tester) async {
      await pumpForm(tester);

      expect(find.text(l10nEn.customFoodMissingValue), findsNothing);
      expect(find.text(l10nEn.customFoodPrefilledNote('METRO')), findsNothing);
    });
  });
}
