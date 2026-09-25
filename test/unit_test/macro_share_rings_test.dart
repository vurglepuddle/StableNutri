import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/macro_share_rings.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

void main() {
  group('macroEnergyShares', () {
    test('shares are of energy, not of grams', () {
      // 2.7 g carbs, 16 g fat, 21 g protein: fat's 9 kcal/g dominate.
      final shares = macroEnergyShares(carbs: 2.7, fat: 16, protein: 21);
      expect(shares, (carbs: 5, fat: 60, protein: 35));
    });

    test('rounded shares still add up to 100', () {
      // A third each by energy.
      final shares = macroEnergyShares(carbs: 9, fat: 4, protein: 9);
      expect(shares.carbs + shares.fat + shares.protein, 100);
    });

    test('no energy, no shares', () {
      expect(macroEnergyShares(carbs: 0, fat: 0, protein: 0), (
        carbs: 0,
        fat: 0,
        protein: 0,
      ));
      expect(macroEnergyShares(carbs: double.nan, fat: -1, protein: 0), (
        carbs: 0,
        fat: 0,
        protein: 0,
      ));
    });

    test('one macro is the whole of it', () {
      expect(macroEnergyShares(carbs: 0, fat: 100, protein: 0), (
        carbs: 0,
        fat: 100,
        protein: 0,
      ));
    });
  });

  testWidgets('rings show percent inside and grams below, at 2x on 320', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: MacroShareRings(carbs: 2.7, fat: 16, protein: 21),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('16 g'), findsOneWidget);
    expect(find.text('2.7 g'), findsOneWidget);
    final rings = tester.widgetList<CircularPercentIndicator>(
      find.byType(CircularPercentIndicator),
    );
    expect(rings.map((ring) => ring.percent), [0.05, 0.6, 0.35]);
  });
}
