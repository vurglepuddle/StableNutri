import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calorie_gauge_provider.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/presentation/widgets/macro_nutriments_widget.dart';
import 'package:opennutritracker/features/home/presentation/widgets/calorie_range_bar.dart';
import 'package:opennutritracker/features/home/presentation/widgets/dashboard_widget.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:provider/provider.dart';

/// The two gauges are interchangeable, so every case says which one it
/// means. The ring is the non-default, hence the explicit flag here.
Widget _dashboard({
  required double supplied,
  double textScale = 1,
  bool usesKj = false,
  bool usesRangeGauge = false,
  double burned = 500,
  CalorieGaugeProvider? gauge,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(usesKilojoules: usesKj),
      ),
      if (gauge != null)
        ChangeNotifierProvider<CalorieGaugeProvider>.value(value: gauge)
      else
        ChangeNotifierProvider<CalorieGaugeProvider>(
          create: (_) => CalorieGaugeProvider(usesRangeGauge: usesRangeGauge),
        ),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: DashboardWidget(
            totalKcalSupplied: supplied,
            totalKcalBurned: burned,
            dailyIntakeLowerKcal: 1850,
            dailyIntakeUpperKcal: 2100,
            totalCarbsIntake: 200,
            totalFatsIntake: 50,
            totalProteinsIntake: 100,
            totalCarbsGoal: 250,
            totalFatsGoal: 60,
            totalProteinsGoal: 120,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('diary macros wrap inside a phone-width card with large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.delegate.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
                child: const MacroNutrientsView(
                  totalCarbsIntake: 12345,
                  totalFatsIntake: 1234,
                  totalProteinsIntake: 1234,
                  totalCarbsGoal: 99999,
                  totalFatsGoal: 5000,
                  totalProteinsGoal: 5000,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final usesKj in [false, true]) {
    testWidgets(
      'dashboard fits narrow screens with large numbers and text (kJ: $usesKj)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _dashboard(supplied: 12345, textScale: 1.6, usesKj: usesKj),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('DashboardWidget presents intake toward the configured range', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_dashboard(supplied: 1500));
    await tester.pumpAndSettle();

    final intakeCounter = tester.firstWidget<AnimatedFlipCounter>(
      find.byType(AnimatedFlipCounter),
    );
    expect(intakeCounter.value, 1500);
    expect(find.text('kcal'), findsOneWidget);
    expect(find.text('Range 1850–2100 kcal'), findsOneWidget);
    expect(find.text('350–600 kcal to reach range'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.track_changes_rounded), findsNothing);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
    expect(find.textContaining('kcal left'), findsNothing);
  });

  testWidgets('DashboardWidget uses neutral within-range feedback', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_dashboard(supplied: 1950));
    await tester.pumpAndSettle();

    expect(find.text('within daily range'), findsOneWidget);
  });

  testWidgets('DashboardWidget uses neutral above-range feedback', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_dashboard(supplied: 2200));
    await tester.pumpAndSettle();

    expect(find.text('100 kcal above daily range'), findsOneWidget);
    expect(find.textContaining('too much'), findsNothing);
  });

  testWidgets('the range bar shows the axis, the goal band and the status', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_dashboard(supplied: 1500, usesRangeGauge: true));
    await tester.pumpAndSettle();

    final intakeCounter = tester.firstWidget<AnimatedFlipCounter>(
      find.byType(AnimatedFlipCounter),
    );
    expect(intakeCounter.value, 1500);
    expect(find.text('kcal \u00b7 toward daily range'), findsOneWidget);
    expect(find.text('goal range 1850\u20132100'), findsOneWidget);
    expect(find.text('350\u2013600 kcal to reach range'), findsOneWidget);
    // The axis ends on a rounded ceiling that clears the goal range.
    expect(find.text('2500'), findsOneWidget);
    // Burned energy rides alongside the headline.
    expect(find.text('500'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    // The ring's own header is gone in this mode.
    expect(find.text('Range 1850\u20132100 kcal'), findsNothing);
  });

  testWidgets('the range bar keeps an over-range day short of the axis end', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_dashboard(supplied: 3000, usesRangeGauge: true));
    await tester.pumpAndSettle();

    // The axis grows past the intake rather than pinning the bar to the end,
    // so an over day never reads as a meter maxed out.
    expect(find.text('2500'), findsNothing);
    expect(find.text('3200'), findsOneWidget);
    expect(
      CalorieRangeBar.axisMaxFor(value: 3000, upper: 2100),
      greaterThan(3000),
    );
    expect(find.text('900 kcal above daily range'), findsOneWidget);
    // Reassurance, not a warning.
    expect(find.text("Some days run higher. That's normal."), findsOneWidget);
    expect(find.textContaining('too much'), findsNothing);
  });

  testWidgets('a day inside the range carries no over-range note', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_dashboard(supplied: 1950, usesRangeGauge: true));
    await tester.pumpAndSettle();

    expect(find.text('within daily range'), findsOneWidget);
    expect(find.text("Some days run higher. That's normal."), findsNothing);
  });

  testWidgets('the range bar hides the active figure when nothing is burned', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _dashboard(supplied: 1500, usesRangeGauge: true, burned: 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('ACTIVE'), findsNothing);
  });

  testWidgets('the range bar survives a narrow screen at 1.6x text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _dashboard(supplied: 1500, usesRangeGauge: true, textScale: 1.6),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('flipping the setting swaps the gauge in place', (
    WidgetTester tester,
  ) async {
    // Settings drives the provider, so drive it the same way here rather than
    // remounting: ChangeNotifierProvider.create is not re-run on rebuild.
    final gauge = CalorieGaugeProvider(usesRangeGauge: false);
    await tester.pumpWidget(_dashboard(supplied: 1500, gauge: gauge));
    await tester.pumpAndSettle();
    expect(find.byType(CalorieRangeBar), findsNothing);
    expect(find.byType(CircularPercentIndicator), findsOneWidget);

    gauge.updateUsesRangeGauge(true);
    await tester.pumpAndSettle();
    expect(find.byType(CalorieRangeBar), findsOneWidget);
    expect(find.byType(CircularPercentIndicator), findsNothing);
    // Same numbers, different shape.
    expect(find.text('350–600 kcal to reach range'), findsOneWidget);
  });
}
