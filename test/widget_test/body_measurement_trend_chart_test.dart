import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/features/measurements/presentation/widgets/body_measurement_trend_chart.dart';
import 'package:opennutritracker/generated/l10n.dart';

void main() {
  for (final window in [30, 1800]) {
    for (final scale in [1.0, 1.6]) {
      for (final imperial in [false, true]) {
        for (final spread in [0.0, 0.2, 15.0]) {
          testWidgets(
            'measurement axes fit $window days, ${scale}x, imperial $imperial, spread $spread',
            (tester) async {
              tester.view.physicalSize = const Size(320, 600);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final today = DateUtils.dateOnly(DateTime.now());
              final entries = [
                BodyMeasurementLogEntity(
                  date: today.subtract(Duration(days: window - 1)),
                  waistCm: 69,
                ),
                BodyMeasurementLogEntity(date: today, waistCm: 69 + spread),
                BodyMeasurementLogEntity(
                  date: today.add(const Duration(days: 1)),
                  waistCm: 99,
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
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 36),
                        child: BodyMeasurementTrendChart(
                          entries: entries,
                          type: BodyMeasurementType.waist,
                          usesImperialLengthUnits: imperial,
                          windowDays: window,
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              Finder labels(String prefix) => find.byWidgetPredicate(
                (widget) =>
                    widget is Text &&
                    widget.key is ValueKey<String> &&
                    (widget.key as ValueKey<String>).value.startsWith(prefix),
              );
              final dates = labels('measurement-chart-date-');
              expect(dates, findsNWidgets(2));
              final dateRects = [
                for (final element in dates.evaluate())
                  tester.getRect(find.byWidget(element.widget)),
              ]..sort((a, b) => a.left.compareTo(b.left));
              final bounds = tester.getRect(find.byType(LineChart));
              expect(dateRects.first.left, greaterThanOrEqualTo(bounds.left));
              expect(dateRects.last.right, lessThanOrEqualTo(bounds.right));
              expect(
                dateRects.last.left - dateRects.first.right,
                greaterThanOrEqualTo(8),
              );
              final values = labels('measurement-chart-value-');
              expect(values.evaluate().length, inInclusiveRange(1, 5));
              expect(
                values
                    .evaluate()
                    .map((element) => (element.widget as Text).data)
                    .toSet()
                    .length,
                values.evaluate().length,
              );
              final valueRects = [
                for (final element in values.evaluate())
                  tester.getRect(find.byWidget(element.widget)),
              ]..sort((a, b) => a.top.compareTo(b.top));
              for (var i = 0; i < valueRects.length; i++) {
                expect(valueRects[i].top, greaterThanOrEqualTo(bounds.top));
                expect(
                  valueRects[i].bottom,
                  lessThanOrEqualTo(dateRects.first.top),
                );
                if (i > 0) {
                  expect(
                    valueRects[i].top - valueRects[i - 1].bottom,
                    greaterThanOrEqualTo(8),
                  );
                }
              }
              expect(
                tester
                    .widget<LineChart>(find.byType(LineChart))
                    .data
                    .lineBarsData
                    .single
                    .spots,
                hasLength(2),
              );
            },
          );
        }
      }
    }
  }
}
