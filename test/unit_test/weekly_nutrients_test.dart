import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/features/trends/domain/weekly_nutrients.dart';
import 'package:opennutritracker/features/trends/presentation/weekly_nutrients_card.dart';
import 'package:opennutritracker/generated/l10n.dart';

IntakeEntity intake(DateTime date, double? fiber, {double amount = 100}) {
  final json = MealDBO.fromMealEntity(MealEntity.empty()).toJson();
  final nutrients = MealEntity.empty().nutriments;
  json['nutriments'] = {
    'energyKcal100': nutrients.energyKcal100,
    'fiber100': fiber,
  };
  return IntakeEntity(
    id: '$date',
    unit: 'g',
    amount: amount,
    type: IntakeTypeEntity.breakfast,
    dateTime: date,
    meal: MealEntity.fromMealDBO(MealDBO.fromJson(json)),
  );
}

void main() {
  test(
    'totals grams and averages logged days without inventing empty days',
    () {
      final week = WeeklyNutrients.calculate([
        intake(DateTime(2026, 10, 1, 12), 10, amount: 150),
        intake(DateTime(2026, 10, 7, 12), 0),
        intake(DateTime(2026, 9, 30, 12), 100),
        intake(DateTime(2026, 10, 8, 12), 100),
      ], endDay: DateTime(2026, 10, 7));
      expect(week.loggedDays, 2);
      expect(week.nutrients[WeeklyNutrient.fiber]!.total, 15);
      expect(week.nutrients[WeeklyNutrient.fiber]!.dailyAverage, 7.5);
      expect(week.nutrients[WeeklyNutrient.sodium]!.total, isNull);
    },
  );
  test(
    'unknown is partial and withholds averages; offset preserves imported labels',
    () {
      final week = WeeklyNutrients.calculate(
        [
          intake(DateTime(2026, 10, 1), 4), // Imported date label stays Oct 1.
          intake(
            DateTime(2026, 10, 1, 4),
            100,
          ), // Before 04:30 belongs to Sep 30.
          intake(DateTime(2026, 10, 8, 4), null), // Belongs to Oct 7.
        ],
        endDay: DateTime(2026, 10, 7),
        offsetMinutes: 270,
      );
      expect(week.loggedDays, 2);
      expect(week.nutrients[WeeklyNutrient.fiber]!.total, 4);
      expect(week.nutrients[WeeklyNutrient.fiber]!.missingFoods, 1);
      expect(week.nutrients[WeeklyNutrient.fiber]!.dailyAverage, isNull);
    },
  );
  for (final scale in [1.3, 1.6, 2.0]) {
    testWidgets('weekly card fits 320px at $scale', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final week = WeeklyNutrients.calculate([
        intake(DateTime(2026, 10, 7), 5),
      ], endDay: DateTime(2026, 10, 7));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: WeeklyNutrientsCard(summary: week),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Weekly nutrients'), findsOneWidget);
      await tester.tap(find.text('Weekly nutrients'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
