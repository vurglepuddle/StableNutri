import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calorie_gauge_provider.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/home/presentation/widgets/calorie_range_bar.dart';
import 'package:opennutritracker/features/home/presentation/widgets/dashboard_widget.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

Widget _dashboard({required double supplied, required double carbs}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => EnergyUnitProvider()),
      ChangeNotifierProvider(
        create: (_) => CalorieGaugeProvider(usesRangeGauge: true),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DashboardWidget(
            totalKcalSupplied: supplied,
            totalKcalBurned: 0,
            dailyIntakeLowerKcal: 1350,
            dailyIntakeUpperKcal: 1600,
            totalCarbsIntake: carbs,
            totalFatsIntake: 40,
            totalProteinsIntake: 50,
            totalCarbsGoal: 250,
            totalFatsGoal: 60,
            totalProteinsGoal: 100,
          ),
        ),
      ),
    ),
  );
}

/// The goal band: the only piece of the bar that does not start at its left.
double _bandLeft(WidgetTester tester) => tester
    .widget<Positioned>(
      find.descendant(
        of: find.byType(CalorieRangeBar),
        matching: find.byWidgetPredicate(
          (w) => w is Positioned && (w.left ?? 0) > 0,
        ),
      ),
    )
    .left!;

double _carbsBar(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator).first)
    .value!;

void main() {
  testWidgets('moving to another day glides the bar and the macros', (
    tester,
  ) async {
    await tester.pumpWidget(_dashboard(supplied: 1064, carbs: 100));
    await tester.pumpAndSettle();
    final bandBefore = _bandLeft(tester);
    expect(_carbsBar(tester), 0.4);

    // An over-range day rescales the axis, so the goal band moves left.
    await tester.pumpWidget(_dashboard(supplied: 3000, carbs: 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final bandMidway = _bandLeft(tester);
    final carbsMidway = _carbsBar(tester);

    await tester.pumpAndSettle();
    final bandAfter = _bandLeft(tester);
    expect(bandAfter, lessThan(bandBefore));
    expect(bandMidway, allOf(lessThan(bandBefore), greaterThan(bandAfter)));
    expect(carbsMidway, allOf(greaterThan(0.4), lessThan(0.8)));
    expect(_carbsBar(tester), 0.8);
  });

  testWidgets('a rebuild with the same numbers leaves the bar at rest', (
    tester,
  ) async {
    await tester.pumpWidget(_dashboard(supplied: 1064, carbs: 100));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_dashboard(supplied: 1064, carbs: 100));
    // Nothing to animate, so nothing is scheduled.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
