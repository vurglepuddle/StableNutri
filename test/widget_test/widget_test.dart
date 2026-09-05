import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/presentation/widgets/macro_nutriments_widget.dart';
import 'package:opennutritracker/features/home/presentation/widgets/dashboard_widget.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

Widget _dashboard({
  required double supplied,
  double textScale = 1,
  bool usesKj = false,
}) {
  return ChangeNotifierProvider<EnergyUnitProvider>(
    create: (_) => EnergyUnitProvider(usesKilojoules: usesKj),
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
            totalKcalBurned: 500,
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
}
