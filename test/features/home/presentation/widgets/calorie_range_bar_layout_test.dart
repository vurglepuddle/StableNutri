import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/features/home/presentation/widgets/calorie_range_bar.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../../../helpers/font_loading.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFont);

  Future<void> render(WidgetTester tester, double width, {double scale = 1}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppPalette.light),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: const CalorieRangeBar(
                    value: 1500,
                    lower: 1850,
                    upper: 2100,
                    burned: 1230,
                    unitLabel: 'kcal',
                    statusLabel: '350–600 left',
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets(
    'separator gaps shrink before burned energy moves to another line',
    (tester) async {
      await render(tester, 340);
      await tester.pumpAndSettle();
      final wideGap =
          tester.getRect(find.text('350–600 left')).left -
          tester.getRect(find.text('kcal')).right;

      await render(tester, 250);
      await tester.pumpAndSettle();
      final unit = tester.getRect(find.text('kcal'));
      final status = tester.getRect(find.text('350–600 left'));
      final burned = tester.getRect(find.text('1230'));
      expect(burned.center.dy, closeTo(unit.center.dy, 0.5));
      expect(status.center.dy, closeTo(unit.center.dy, 0.5));
      expect(status.left - unit.right, lessThan(wideGap));
      expect(
        tester
            .widget<AnimatedFlipCounter>(find.byType(AnimatedFlipCounter))
            .textStyle!
            .fontSize,
        23,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large accessibility text wraps without hiding energy values', (
    tester,
  ) async {
    await render(tester, 240, scale: 2);
    await tester.pumpAndSettle();
    expect(find.text('350–600 left'), findsOneWidget);
    expect(find.text('1230'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
