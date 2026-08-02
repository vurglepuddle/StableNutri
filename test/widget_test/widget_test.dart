import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/home/presentation/widgets/dashboard_widget.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

Widget _dashboard({required double supplied}) {
  return ChangeNotifierProvider<EnergyUnitProvider>(
    create: (_) => EnergyUnitProvider(),
    child: MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      home: DashboardWidget(
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
  );
}

void main() {
  testWidgets('DashboardWidget presents intake toward the configured range', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_dashboard(supplied: 1500));
    await tester.pumpAndSettle();

    final intakeCounter = tester.firstWidget<AnimatedFlipCounter>(
      find.byType(AnimatedFlipCounter),
    );
    expect(intakeCounter.value, 1500);
    expect(find.text('kcal · toward daily range'), findsOneWidget);
    expect(find.text('1850–2100 kcal'), findsOneWidget);
    expect(find.text('350 kcal to reach range'), findsOneWidget);
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
