import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Measured numeric titles that keep endpoint labels apart from nearby ticks.
class ChartValueAxis {
  final SideTitles titles;

  ChartValueAxis._(this.titles);

  factory ChartValueAxis({
    required BuildContext context,
    required double min,
    required double max,
    required double height,
    required TextStyle? style,
    required String keyPrefix,
  }) {
    Size measure(String text) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final labelHeight = measure('0123456789').height;
    final count = (height / (labelHeight + 16)).floor().clamp(2, 5);
    final rawStep = (max - min) / (count - 1);
    final magnitude = math
        .pow(10, (math.log(rawStep) / math.ln10).floor())
        .toDouble();
    final step =
        [1, 2, 5, 10].firstWhere((n) => n * magnitude >= rawStep) * magnitude;
    final decimals = math
        .max(0, -(math.log(step) / math.ln10).floor())
        .clamp(0, 4);
    final width = math.max(
      measure(min.toStringAsFixed(decimals)).width,
      measure(max.toStringAsFixed(decimals)).width,
    );
    return ChartValueAxis._(
      SideTitles(
        showTitles: true,
        reservedSize: width.ceilToDouble() + 12,
        interval: step,
        getTitlesWidget: (value, meta) {
          final edgeGap = (labelHeight * 1.5 + 8) / height * (max - min);
          if (value != min &&
              value != max &&
              (value - min < edgeGap || max - value < edgeGap)) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            key: ValueKey((keyPrefix, value, width, height)),
            meta: meta,
            fitInside: SideTitleFitInsideData.fromTitleMeta(
              meta,
              enabled: true,
            ),
            child: Text(
              value.toStringAsFixed(decimals),
              key: ValueKey('$keyPrefix$value'),
              maxLines: 1,
              softWrap: false,
              style: style,
            ),
          );
        },
      ),
    );
  }
}
