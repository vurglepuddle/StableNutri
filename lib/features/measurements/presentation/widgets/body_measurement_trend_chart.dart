import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/presentation/widgets/chart_value_axis.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/generated/l10n.dart';

class BodyMeasurementTrendChart extends StatelessWidget {
  final List<BodyMeasurementLogEntity> entries;
  final BodyMeasurementType type;
  final bool usesImperialLengthUnits;
  final int windowDays;

  const BodyMeasurementTrendChart({
    super.key,
    required this.entries,
    required this.type,
    required this.usesImperialLengthUnits,
    required this.windowDays,
  });

  double _display(double value) {
    if (type == BodyMeasurementType.bodyFat || !usesImperialLengthUnits) {
      return value;
    }
    return UnitCalc.cmToInches(value);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: windowDays - 1));
    final points = [
      for (final entry in entries)
        if (!entry.date.isBefore(start) &&
            !entry.date.isAfter(today) &&
            entry.valueFor(type) != null)
          (
            date: DateTime(entry.date.year, entry.date.month, entry.date.day),
            value: _display(entry.valueFor(type)!),
          ),
    ]..sort((a, b) => a.date.compareTo(b.date));

    if (points.length < 2) {
      return SizedBox(
        height: 132,
        child: Center(
          child: Text(
            S.of(context).measurementsChartEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    final values = points.map((point) => point.value).toList();
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final spread = maxValue - minValue;
    final padding = spread == 0
        ? (maxValue.abs() * 0.04).clamp(1.0, 5.0)
        : spread * 0.2;
    final primary = Theme.of(context).colorScheme.primary;
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;

    return Semantics(
      identifier: 'measurements-trend-chart',
      label: S.of(context).measurementsChartSemantics(points.length),
      child: SizedBox(
        height: 156,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final style = Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: palette.textMuted);
            final locale = Localizations.localeOf(context).toLanguageTag();
            var dateFormat = windowDays > 365
                ? DateFormat.yMMM(locale)
                : DateFormat.MMMd(locale);
            Size measureDates() {
              var size = Size.zero;
              for (final date in [start, today]) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: dateFormat.format(date),
                    style: DefaultTextStyle.of(context).style.merge(style),
                  ),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                )..layout();
                size = Size(
                  size.width > painter.width ? size.width : painter.width,
                  size.height > painter.height ? size.height : painter.height,
                );
                painter.dispose();
              }
              return size;
            }

            var dateSize = measureDates();
            if (dateSize.width * 2 + 16 > constraints.maxWidth) {
              dateFormat = windowDays > 365
                  ? DateFormat.y(locale)
                  : DateFormat.Md(locale);
              dateSize = measureDates();
            }
            final valueAxis = ChartValueAxis(
              context: context,
              min: minValue - padding,
              max: maxValue + padding,
              height: constraints.maxHeight - dateSize.height - 12,
              style: style,
              keyPrefix: 'measurement-chart-value-',
            );
            return Column(
              children: [
                Expanded(
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: (windowDays - 1).toDouble(),
                      minY: minValue - padding,
                      maxY: maxValue + padding,
                      clipData: const FlClipData.all(),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) =>
                            FlLine(color: palette.border, strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (spots) => [
                            for (final spot in spots)
                              LineTooltipItem(
                                spot.y.toStringAsFixed(1),
                                TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onInverseSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(sideTitles: valueAxis.titles),
                        bottomTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (final point in points)
                              FlSpot(
                                point.date.difference(start).inDays.toDouble(),
                                point.value,
                              ),
                          ],
                          isCurved: true,
                          preventCurveOverShooting: true,
                          color: primary,
                          barWidth: 3,
                          dotData: FlDotData(show: points.length <= 10),
                          belowBarData: BarAreaData(
                            show: true,
                            color: primary.withValues(alpha: 0.1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final day in [0, windowDays - 1])
                      Text(
                        dateFormat.format(start.add(Duration(days: day))),
                        key: ValueKey('measurement-chart-date-$day'),
                        maxLines: 1,
                        softWrap: false,
                        style: style,
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
