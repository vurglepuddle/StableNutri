import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/calorie_gauge_provider.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/home/presentation/widgets/dashboard_widget.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../../../helpers/font_loading.dart';

Widget _dashboard({
  required double textScale,
  double lower = 1350,
  double upper = 1600,
  double supplied = 1064,
  double burned = 0,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => EnergyUnitProvider()),
      ChangeNotifierProvider(
        create: (_) => CalorieGaugeProvider(usesRangeGauge: true),
      ),
    ],
    child: MaterialApp(
      theme: buildAppTheme(AppPalette.light),
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
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
            dailyIntakeLowerKcal: lower,
            dailyIntakeUpperKcal: upper,
            totalCarbsIntake: 555,
            totalFatsIntake: 555,
            totalProteinsIntake: 555,
            totalCarbsGoal: 555,
            totalFatsGoal: 555,
            totalProteinsGoal: 555,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadAppFont);

  // A Pixel 9a at its display size setting: 1080 px at 460 dpi.
  void usePhoneWidth(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2424);
    tester.view.devicePixelRatio = 460 / 160;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// How far the headline had to shrink to fit its row: 1 is full size.
  double headlineScale(WidgetTester tester) {
    final caption = find.text('kcal · 286–536 left');
    return tester.getRect(caption).width /
        tester.renderObject<RenderBox>(caption).size.width;
  }

  testWidgets('the headline and its status fit with 1.3x text', (tester) async {
    usePhoneWidth(tester);
    await tester.pumpWidget(_dashboard(textScale: 1.3));
    await tester.pumpAndSettle();
    expect(headlineScale(tester), greaterThan(0.95));

    // Burned energy shares the row, so the headline gives a little. The old
    // "toward daily range" caption beside a side-by-side figure was at 0.56.
    await tester.pumpWidget(_dashboard(textScale: 1.3, burned: 500));
    await tester.pumpAndSettle();
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(headlineScale(tester), greaterThan(0.75));
  });

  testWidgets('"555/555 g" fits a macro tile at full size with 1.3x text', (
    tester,
  ) async {
    usePhoneWidth(tester);
    await tester.pumpWidget(_dashboard(textScale: 1.3));
    await tester.pumpAndSettle();

    final line = tester.getSize(find.text('fat')).height;
    for (final amount in find.text('555/555 g').evaluate()) {
      final box = amount.renderObject! as RenderBox;
      // One line, drawn as wide as it lays out: the tile did not have to
      // wrap or shrink it.
      expect(box.size.height, lessThan(line * 1.5));
      final drawn = tester.getRect(find.byWidget(amount.widget));
      expect(drawn.width, moreOrLessEquals(box.size.width, epsilon: 0.01));
    }
    expect(find.text('555/555 g'), findsNWidgets(3));
  });

  testWidgets('the macro amount stays on one line at 2x text', (tester) async {
    usePhoneWidth(tester);
    await tester.pumpWidget(_dashboard(textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final line = tester.getSize(find.text('fat')).height;
    for (final amount in find.text('555/555 g').evaluate()) {
      // Same style ladder as the label: a wrapped amount would be two lines.
      expect(
        (amount.renderObject! as RenderBox).size.height,
        lessThan(line * 1.5),
      );
    }
  });

  testWidgets('the bar names the range once and says what is left', (
    tester,
  ) async {
    usePhoneWidth(tester);
    await tester.pumpWidget(_dashboard(textScale: 1));
    await tester.pumpAndSettle();

    expect(find.text('goal range 1350–1600'), findsOneWidget);
    expect(find.text('kcal · 286–536 left'), findsOneWidget);
    expect(find.textContaining('toward'), findsNothing);
    expect(find.textContaining('reach'), findsNothing);
  });

  testWidgets('a single goal reads as a goal, not a range', (tester) async {
    usePhoneWidth(tester);
    await tester.pumpWidget(_dashboard(textScale: 1, lower: 1500, upper: 1500));
    await tester.pumpAndSettle();

    expect(find.text('goal 1500'), findsOneWidget);
    expect(find.text('kcal · 436 left'), findsOneWidget);
    expect(find.textContaining('range'), findsNothing);
  });
}
