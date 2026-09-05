import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/presentation/widgets/chart_value_axis.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Smoothed weight trend line shared by the weight-history screen and the
/// Trends view, so both render the same chart with a dated axis, a shaded
/// corridor, dots on each reading, and a curved line.
///
/// [windowDays] sets how far back the chart looks; entries older than that
/// are dropped. The y-range includes both readings and a configured corridor
/// so the relationship between them remains visible.
class WeightTrendChart extends StatelessWidget {
  final List<WeightLogEntity> entries;
  final BodyWeightUnit bodyWeightUnit;
  final double? weightCorridorLowerKg;
  final double? weightCorridorUpperKg;
  final int windowDays;
  final double chartHeight;

  const WeightTrendChart({
    super.key,
    required this.entries,
    required this.bodyWeightUnit,
    this.weightCorridorLowerKg,
    this.weightCorridorUpperKg,
    this.windowDays = 30,
    this.chartHeight = 220,
  });

  /// Converts a stored kg value to the chart's y-axis unit.
  double _toChartY(double kg) {
    switch (bodyWeightUnit) {
      case BodyWeightUnit.kg:
        return kg;
      case BodyWeightUnit.lb:
        return UnitCalc.kgToLbs(kg);
      case BodyWeightUnit.st:
        // Decimal stones: total lbs / 14. One decimal is enough for the axis.
        return kg * 2.20462 / 14;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineColor = theme.colorScheme.primary;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // windowDays days ending today (today sits at the right edge), matching
    // how the calorie/water charts window their range.
    final windowStart = today.subtract(Duration(days: windowDays - 1));

    final inWindow =
        entries
            .where(
              (e) => !e.date.isBefore(windowStart) && !e.date.isAfter(today),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    if (inWindow.length < 2) {
      return Padding(
        key: const Key('weightHistoryChartEmptyState'),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: SizedBox(
          height: chartHeight,
          child: Center(
            child: Text(
              S.of(context).weightHistoryChartEmptyState,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    final spots = <FlSpot>[
      for (final entry in inWindow)
        FlSpot(
          // x = days since the window start, so today sits at x = windowDays.
          entry.date.difference(windowStart).inDays.toDouble(),
          _toChartY(entry.weightKg),
        ),
    ];

    final hasCorridor =
        weightCorridorLowerKg != null &&
        weightCorridorUpperKg != null &&
        weightCorridorLowerKg! < weightCorridorUpperKg!;
    final corridorLowerY = hasCorridor
        ? _toChartY(weightCorridorLowerKg!)
        : null;
    final corridorUpperY = hasCorridor
        ? _toChartY(weightCorridorUpperKg!)
        : null;
    final plottedY = [
      ...spots.map((s) => s.y),
      ?corridorLowerY,
      ?corridorUpperY,
    ];
    final minY = plottedY.reduce((a, b) => a < b ? a : b);
    final maxY = plottedY.reduce((a, b) => a > b ? a : b);
    // Pad so points don't sit on the edges. When all weights are identical we
    // still need a non-zero range or fl_chart throws.
    final yPadding = ((maxY - minY) * 0.15).clamp(0.5, 5.0);

    final localeTag = Localizations.localeOf(context).toLanguageTag();
    // Match the rendered text, including accessibility scale and locale.
    Size measureDates(DateFormat format) {
      var width = 0.0;
      var height = 0.0;
      for (final day in [
        windowStart,
        today,
        for (var month = 1; month <= 12; month++)
          DateTime(today.year, month, 28),
      ]) {
        final painter = TextPainter(
          text: TextSpan(
            text: format.format(day),
            style: DefaultTextStyle.of(
              context,
            ).style.merge(theme.textTheme.labelSmall),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        if (painter.width > width) width = painter.width;
        if (painter.height > height) height = painter.height;
        painter.dispose();
      }
      return Size(width, height);
    }

    return Padding(
      key: const Key('weightHistoryChart'),
      padding: const EdgeInsets.fromLTRB(16, 16, 24, 16),
      child: SizedBox(
        height: chartHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final valueAxis = ChartValueAxis(
              context: context,
              min: minY - yPadding,
              max: maxY + yPadding,
              height:
                  chartHeight -
                  measureDates(DateFormat.y(localeTag)).height -
                  12,
              style: theme.textTheme.labelSmall,
              keyPrefix: 'weight-chart-value-',
            );
            final plotWidth =
                constraints.maxWidth - valueAxis.titles.reservedSize;
            var dateFormat = windowDays > 365
                ? DateFormat.yMMM(localeTag)
                : DateFormat.MMMd(localeTag);
            var labelSize = measureDates(dateFormat);
            if (labelSize.width * 2 + 16 > plotWidth) {
              // Keep endpoint labels readable on narrow cards at large text
              // scale: years for multi-year history, numeric dates otherwise.
              dateFormat = windowDays > 365
                  ? DateFormat.y(localeTag)
                  : DateFormat.Md(localeTag);
              labelSize = measureDates(dateFormat);
            }
            final labelCount = (plotWidth / (labelSize.width + 16))
                .floor()
                .clamp(2, 6);
            final maxX = (windowDays - 1).toDouble();
            final labelInterval = (maxX / (labelCount - 1))
                .ceilToDouble()
                .clamp(1, double.infinity)
                .toDouble();
            return LineChart(
              LineChartData(
                minX: 0,
                maxX: (windowDays - 1).toDouble(),
                minY: minY - yPadding,
                maxY: maxY + yPadding,
                rangeAnnotations: RangeAnnotations(
                  horizontalRangeAnnotations: [
                    if (corridorLowerY != null && corridorUpperY != null)
                      HorizontalRangeAnnotation(
                        y1: corridorLowerY,
                        y2: corridorUpperY,
                        color: lineColor.withValues(alpha: 0.10),
                      ),
                  ],
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(sideTitles: valueAxis.titles),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: labelSize.height + 12,
                      interval: labelInterval,
                      getTitlesWidget: (value, meta) {
                        // fl_chart adds the end date even when it falls between
                        // regular ticks. Suppress a nearby tick so they cannot pile up.
                        if (value != maxX &&
                            value != 0 &&
                            maxX - value < labelInterval * 0.8) {
                          return const SizedBox.shrink();
                        }
                        final day = windowStart.add(
                          Duration(days: value.round()),
                        );
                        return SideTitleWidget(
                          key: ValueKey((day, labelSize)),
                          meta: meta,
                          space: 6,
                          fitInside: SideTitleFitInsideData.fromTitleMeta(
                            meta,
                            enabled: true,
                          ),
                          child: Text(
                            dateFormat.format(day),
                            key: ValueKey('weight-chart-date-${value.round()}'),
                            maxLines: 1,
                            softWrap: false,
                            style: theme.textTheme.labelSmall,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (corridorLowerY != null)
                      HorizontalLine(
                        y: corridorLowerY,
                        color: lineColor.withValues(alpha: 0.55),
                        strokeWidth: 1,
                        dashArray: const [6, 4],
                      ),
                    if (corridorUpperY != null)
                      HorizontalLine(
                        y: corridorUpperY,
                        color: lineColor.withValues(alpha: 0.55),
                        strokeWidth: 1,
                        dashArray: const [6, 4],
                      ),
                  ],
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: lineColor,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                            radius: 3,
                            color: lineColor,
                            strokeWidth: 0,
                          ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
