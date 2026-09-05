import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/weight_trend_chart.dart';
import 'package:opennutritracker/generated/l10n.dart';

void main() {
  for (final window in [7, 30, 365, 1800]) {
    for (final textScale in [1.0, 1.6]) {
      testWidgets(
        '$window-day weight chart keeps dates readable at ${textScale}x text',
        (tester) async {
          tester.view.physicalSize = const Size(320, 600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final entries = [
            for (var day = 0; day < window; day++)
              WeightLogEntity(
                date: today.subtract(Duration(days: day)),
                weightKg: 72 + day % 3 * 0.2,
              ),
          ];
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: const [
                S.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: S.delegate.supportedLocales,
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: WeightTrendChart(
                      entries: entries,
                      bodyWeightUnit: BodyWeightUnit.kg,
                      windowDays: window,
                      weightCorridorLowerKg: 70,
                      weightCorridorUpperKg: 74,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final labels = find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.key is ValueKey<String> &&
                (widget.key as ValueKey<String>).value.startsWith(
                  'weight-chart-date-',
                ),
          );
          expect(labels.evaluate().length, inInclusiveRange(2, 6));
          final rectangles = [
            for (final element in labels.evaluate())
              tester.getRect(find.byWidget(element.widget)),
          ]..sort((a, b) => a.left.compareTo(b.left));
          for (var index = 1; index < rectangles.length; index++) {
            expect(
              rectangles[index].left - rectangles[index - 1].right,
              greaterThanOrEqualTo(8),
            );
          }
          for (final rectangle in rectangles) {
            expect(rectangle.left, greaterThanOrEqualTo(16));
            expect(rectangle.right, lessThanOrEqualTo(304));
          }
          final chart = tester.widget<LineChart>(find.byType(LineChart));
          final valueLabels = find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.key is ValueKey<String> &&
                (widget.key as ValueKey<String>).value.startsWith(
                  'weight-chart-value-',
                ),
          );
          expect(valueLabels.evaluate().length, inInclusiveRange(1, 5));
          final values = [
            for (final element in valueLabels.evaluate())
              tester.getRect(find.byWidget(element.widget)),
          ]..sort((a, b) => a.top.compareTo(b.top));
          final chartBounds = tester.getRect(find.byType(LineChart));
          for (var i = 0; i < values.length; i++) {
            expect(values[i].top, greaterThanOrEqualTo(chartBounds.top));
            expect(values[i].bottom, lessThanOrEqualTo(rectangles.first.top));
            if (i > 0) {
              expect(
                values[i].top - values[i - 1].bottom,
                greaterThanOrEqualTo(8),
              );
            }
          }
          expect(
            chart.data.lineBarsData.single.spots,
            hasLength(entries.length),
          );
          final corridor =
              chart.data.rangeAnnotations.horizontalRangeAnnotations.single;
          expect(corridor.y1, 70);
          expect(corridor.y2, 74);
          if (window > 365) {
            expect(
              chart.data.titlesData.bottomTitles.sideTitles.interval,
              greaterThan(30),
            );
            for (final element in labels.evaluate()) {
              expect((element.widget as Text).data, matches(RegExp(r'\d{4}')));
            }
          }
        },
      );
    }
  }
}
