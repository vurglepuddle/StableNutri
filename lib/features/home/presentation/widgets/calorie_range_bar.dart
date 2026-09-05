import 'dart:math' as math;

import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Today's energy as a linear range bar — the "2a" exploration.
///
/// The ring answers "how far round am I?", which only makes sense against a
/// single target. Stable's goal is a *range*, and a straight axis can show the
/// thing a circle cannot: where the range sits, how far along it you are, and
/// how much headroom is left, all at once and all to the same scale.
///
/// Reads exactly the same numbers as the ring; the two are interchangeable
/// through Settings and neither is the "real" one.
class CalorieRangeBar extends StatelessWidget {
  const CalorieRangeBar({
    super.key,
    required this.value,
    required this.lower,
    required this.upper,
    required this.burned,
    required this.unitLabel,
    required this.statusLabel,
  });

  /// All values arrive already converted to the user's display unit, so this
  /// widget never has to know whether it is drawing kcal or kJ.
  final double value;
  final double lower;
  final double upper;
  final double burned;
  final String unitLabel;
  final String statusLabel;

  static const double _barHeight = 18;

  /// Headroom past the top of the goal range, so the range does not sit flush
  /// against the end of the axis and going over still has somewhere to go.
  static const double _headroom = 1.15;

  /// Headroom past an over-range day, so the fill never reaches the end.
  static const double _headroomOver = 1.05;

  /// The axis top: enough to clear the goal range, and always enough to show
  /// the day's actual intake with room to spare when that runs past the range.
  ///
  /// The headroom on the value is the point. A bar pinned hard against the end
  /// of its track reads as a meter maxed out — an alarm. Leaving space past the
  /// fill says "this is simply where the day landed" instead.
  static double axisMaxFor({required double value, required double upper}) {
    final wanted = math.max(upper * _headroom, value * _headroomOver);
    return _niceCeil(wanted);
  }

  /// Rounds up to a readable tick — 2,415 becomes 2,500, not 2,415.
  static double _niceCeil(double raw) {
    if (!raw.isFinite || raw <= 0) return 100;
    final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor());
    final step = math.max(1.0, magnitude / 10);
    return (raw / step).ceil() * step;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final textTheme = theme.textTheme;

    final axisMax = axisMaxFor(value: value, upper: upper);
    final bandStart = (lower / axisMax).clamp(0.0, 1.0);
    final bandEnd = (upper / axisMax).clamp(0.0, 1.0);
    final fill = (value / axisMax).clamp(0.0, 1.0);
    // Everything past the top of the range is drawn in peach: a different
    // colour rather than a louder one, so an over day reads as "this is where
    // it landed", not as a warning.
    final withinEnd = (math.min(value, upper) / axisMax).clamp(0.0, 1.0);
    final isOver = value > upper;
    final rangeLabel = s.calorieGaugeRangeLabel(
      lower.round().toString(),
      upper.round().toString(),
    );

    return Semantics(
      label: '${value.round()} $unitLabel. $rangeLabel. $statusLabel',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _buildHeadline(s, textTheme, palette)),
              const SizedBox(width: Dimens.spacing8),
              _buildBurned(s, textTheme, palette),
            ],
          ),
          const SizedBox(height: Dimens.spacing16),
          _buildBar(palette, bandStart, bandEnd, fill, withinEnd),
          const SizedBox(height: Dimens.spacing8),
          _buildScale(axisMax, rangeLabel, textTheme, palette),
          const SizedBox(height: Dimens.spacing12),
          SizedBox(
            width: double.infinity,
            child: Text(
              statusLabel,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isOver) ...[
            const SizedBox(height: Dimens.spacing4),
            SizedBox(
              width: double.infinity,
              child: Text(
                s.calorieGaugeOverRangeNote,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(color: palette.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeadline(S s, TextTheme textTheme, AppPalette palette) {
    // The number and its caption share a baseline, and shrink together rather
    // than wrapping when the unit is long or the text scale is large.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedFlipCounter(
            value: value.round(),
            duration: AppMotion.durationLong,
            curve: AppMotion.emphasized,
            thousandSeparator: ' ',
            textStyle: textTheme.displaySmall?.copyWith(height: 1),
          ),
          const SizedBox(width: Dimens.spacing8),
          Text(
            '$unitLabel · ${s.calorieGaugeTowardRangeLabel}',
            style: textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildBurned(S s, TextTheme textTheme, AppPalette palette) {
    if (burned <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(burned.round().toString(), style: textTheme.labelLarge),
        const SizedBox(width: 4),
        Text(
          s.calorieGaugeActiveLabel.toUpperCase(),
          style: textTheme.labelSmall?.copyWith(
            color: palette.textMuted,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _buildBar(
    AppPalette palette,
    double bandStart,
    double bandEnd,
    double fill,
    double withinEnd,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final radius = BorderRadius.circular(_barHeight);
        return SizedBox(
          height: _barHeight,
          width: double.infinity,
          child: Stack(
            children: [
              // The axis itself.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surfaceMuted,
                    borderRadius: radius,
                  ),
                ),
              ),
              // Where the goal range sits on that axis.
              Positioned(
                left: width * bandStart,
                width: math.max(2, width * (bandEnd - bandStart)),
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(Dimens.spacing4),
                  ),
                ),
              ),
              // How far along it today has got. One tween drives both
              // segments, so the green fills first and the peach only appears
              // once the animation passes the top of the range.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: fill),
                  duration: AppMotion.durationLong,
                  curve: AppMotion.emphasized,
                  builder: (context, animated, _) {
                    final within = math.min(animated, withinEnd);
                    return SizedBox(
                      width: width * animated,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: palette.overRange,
                                borderRadius: radius,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child: SizedBox(
                              width: width * within,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      palette.accent.withValues(alpha: 0.55),
                                      palette.accent,
                                    ],
                                  ),
                                  borderRadius: radius,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScale(
    double axisMax,
    String rangeLabel,
    TextTheme textTheme,
    AppPalette palette,
  ) {
    final endStyle = textTheme.bodySmall?.copyWith(color: palette.textMuted);
    return Row(
      children: [
        Text('0', style: endStyle),
        Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                rangeLabel,
                maxLines: 1,
                softWrap: false,
                style: textTheme.labelMedium?.copyWith(color: palette.accent),
              ),
            ),
          ),
        ),
        Text(axisMax.round().toString(), style: endStyle),
      ],
    );
  }
}
