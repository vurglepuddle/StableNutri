import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_nutriments_table.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_food_parser.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../../../fixture/lifesum_export_fixture.dart';

void main() {
  group('LifesumFoodParser', () {
    test('normalizes logged gram totals to Stable per-100-g values', () {
      final result = LifesumFoodParser.parse(
        sanitizedLifesumFiles['food.csv']!,
      );

      expect(result.sourceRowCount, 1);
      expect(result.candidates, hasLength(1));
      expect(result.issues, isEmpty);
      final candidate = result.candidates.single;
      final intake = candidate.intake;
      expect(candidate.basis, LifesumFoodBasis.gramWeight);
      expect(intake.amount, 80);
      expect(intake.unit, 'g');
      expect(intake.type, IntakeTypeEntity.breakfast);
      expect(intake.meal.nutriments.energyKcal100, 375);
      expect(intake.meal.nutriments.carbohydrates100, 62.5);
      expect(intake.meal.nutriments.cholesterol100, 0);
      expect(intake.meal.nutriments.potassium100, 250);
      expect(intake.meal.nutriments.sodium100, 125);
      expect(intake.totalKcal, closeTo(300, 0.000001));
      expect(intake.totalCarbsGram, closeTo(50, 0.000001));
      expect(intake.totalFatsGram, closeTo(6, 0.000001));
      expect(intake.totalProteinsGram, closeTo(10, 0.000001));
    });

    test('uses a non-physical serving basis when gram weight is absent', () {
      final result = LifesumFoodParser.parse(
        _csvWithRows(<String>[
          '2024-01-02,lunch,Example soup,,meal serving,2,,240,30,4,3,0,'
              '8,2,6,0.2,12,0.1',
        ]),
      );

      final candidate = result.candidates.single;
      final intake = candidate.intake;
      expect(candidate.basis, LifesumFoodBasis.sourceServing);
      expect(intake.amount, 2);
      expect(intake.unit, 'serving');
      expect(intake.meal.mealUnit, 'serving');
      expect(intake.meal.servingQuantity, 1);
      expect(intake.meal.servingSize, 'meal serving');
      expect(intake.totalKcal, closeTo(240, 0.000001));
      expect(
        result.issues.single.code,
        LifesumFoodIssueCode.servingBasisFallback,
      );
    });

    test('treats a Calories-labelled row as one logged-total serving', () {
      final result = LifesumFoodParser.parse(
        _csvWithRows(<String>[
          '2024-01-02,snack,Quick energy,,Calories,250,,250,0,0,0,0,0,0,'
              '0,0,0,0',
        ]),
      );

      final candidate = result.candidates.single;
      expect(candidate.basis, LifesumFoodBasis.loggedTotal);
      expect(candidate.intake.amount, 1);
      expect(candidate.intake.totalKcal, closeTo(250, 0.000001));
    });

    test('preserves repeated rows with deterministic occurrence IDs', () {
      const row =
          '2024-01-02,dinner,Example plate,Sample,serving,1,250,500,50,5,4,'
          '0,20,5,15,0.3,30,0.2';
      final csv = _csvWithRows(<String>[row, row]);

      final first = LifesumFoodParser.parse(csv);
      final second = LifesumFoodParser.parse(csv);

      expect(first.candidates, hasLength(2));
      expect(first.intakes[0].id, endsWith('-001'));
      expect(first.intakes[1].id, endsWith('-002'));
      expect(first.intakes[0].id, second.intakes[0].id);
      expect(first.intakes[1].id, second.intakes[1].id);
    });

    test('reconstructs sorted day totals from accepted source totals', () {
      final result = LifesumFoodParser.parse(
        _csvWithRows(<String>[
          '2024-01-03,breakfast,Example one,,g,100,100,200,20,2,3,0,5,1,'
              '4,0.1,10,0.05',
          '2024-01-02,lunch,Example two,,g,50,50,150,15,1,2,0,4,1,3,'
              '0.1,8,0.04',
          '2024-01-02,dinner,Example three,,g,75,75,250,25,3,4,0,6,2,'
              '4,0.2,12,0.06',
        ]),
      );

      expect(result.trackedDays, hasLength(2));
      final firstDay = result.trackedDays.first;
      expect(firstDay.day, DateTime(2024, 1, 2));
      expect(firstDay.intakeCount, 2);
      expect(firstDay.caloriesTracked, 400);
      expect(firstDay.carbsTracked, 40);
      expect(firstDay.fatTracked, 10);
      expect(firstDay.proteinTracked, 20);
    });

    test('places synthetic timestamps safely inside a custom logical day', () {
      const offset = 20 * 60 + 30;
      final result = LifesumFoodParser.parse(
        sanitizedLifesumFiles['food.csv']!,
        dayStartOffsetMinutes: offset,
      );

      final timestamp = result.intakes.single.dateTime;
      expect(timestamp, DateTime(2024, 1, 3, 8, 30, 0, 0, 2));
      expect(
        DayBoundaryCalc.logicalDayOfMinutes(timestamp, offset),
        DateTime(2024, 1, 2),
      );
    });

    test('parses quoted food text without leaking it into generated IDs', () {
      final result = LifesumFoodParser.parse(
        _csvWithRows(<String>[
          '2024-01-02,lunch,"Example, chopped","Brand, synthetic",g,100,'
              '100,200,20,2,3,0,5,1,4,0.1,10,0.05',
        ]),
      );

      final intake = result.intakes.single;
      expect(intake.meal.name, 'Example, chopped');
      expect(intake.meal.brands, 'Brand, synthetic');
      expect(intake.id, isNot(contains('Example')));
      expect(intake.meal.code, isNot(contains('Brand')));
    });

    test('skips invalid rows with value-free structural issues', () {
      final result = LifesumFoodParser.parse(
        _csvWithRows(<String>[
          '2024-02-30,lunch,Example,,g,100,100,200,20,2,3,0,5,1,4,0.1,'
              '10,0.05',
          '2024-01-02,unknown,Example,,g,100,100,200,20,2,3,0,5,1,4,0.1,'
              '10,0.05',
          '2024-01-02,lunch,,,100,100,200,20,2,3,0,5,1,4,0.1,10,0.05',
          '2024-01-02,lunch,Example,,g,-1,100,200,20,2,3,0,5,1,4,0.1,'
              '10,0.05',
          '2024-01-02,lunch,Example,,g,100,100,NaN,20,2,3,0,5,1,4,0.1,'
              '10,0.05',
          '2024-01-02,lunch,Example,,g,100,100,200,-1,2,3,0,5,1,4,0.1,'
              '10,0.05',
        ]),
      );

      expect(result.candidates, isEmpty);
      expect(result.warningCount, 6);
      expect(result.issues.every((issue) => issue.rowNumber != null), isTrue);
    });

    test('missing required headers block the food section', () {
      final result = LifesumFoodParser.parse('date,title\n2024-01-02,Example');

      expect(result.candidates, isEmpty);
      expect(result.blockingIssueCount, greaterThan(0));
      expect(result.issues.every((issue) => issue.rowNumber == null), isTrue);
    });
  });

  testWidgets('synthetic serving basis renders nutrients per serving', (
    tester,
  ) async {
    final result = LifesumFoodParser.parse(
      _csvWithRows(<String>[
        '2024-01-02,lunch,Example soup,,meal serving,2,,240,30,4,3,0,8,2,'
            '6,0.2,12,0.1',
      ]),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.delegate.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MealDetailNutrimentsTable(
                product: result.intakes.single.meal,
                usesImperialUnits: false,
                servingQuantity: 1,
                servingUnit: 'serving',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(S.current.perServingLabel), findsOneWidget);
    expect(find.text('120 kcal'), findsOneWidget);
  });
}

String _csvWithRows(List<String> rows) =>
    '${sanitizedLifesumFiles['food.csv']!.split('\n').first}\n'
    '${rows.join('\n')}\n';
