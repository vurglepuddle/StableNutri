import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/stable_range_calc.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/calorie_gauge_provider.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/home/presentation/widgets/calorie_range_bar.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

class DashboardWidget extends StatefulWidget {
  final double totalKcalSupplied;
  final double totalKcalBurned;
  final double dailyIntakeLowerKcal;
  final double dailyIntakeUpperKcal;
  final double totalCarbsIntake;
  final double totalFatsIntake;
  final double totalProteinsIntake;
  final double totalCarbsGoal;
  final double totalFatsGoal;
  final double totalProteinsGoal;

  const DashboardWidget({
    super.key,
    required this.totalKcalSupplied,
    required this.totalKcalBurned,
    required this.dailyIntakeLowerKcal,
    required this.dailyIntakeUpperKcal,
    required this.totalCarbsIntake,
    required this.totalFatsIntake,
    required this.totalProteinsIntake,
    required this.totalCarbsGoal,
    required this.totalFatsGoal,
    required this.totalProteinsGoal,
  });

  @override
  State<DashboardWidget> createState() => _DashboardWidgetState();
}

class _DashboardWidgetState extends State<DashboardWidget> {
  @override
  Widget build(BuildContext context) {
    final usesKilojoules = context.watch<EnergyUnitProvider>().usesKilojoules;
    // Both gauges read the same numbers; only the shape differs, so the
    // choice lives in a provider rather than in HomeBloc's state.
    final usesRangeGauge = context.watch<CalorieGaugeProvider>().usesRangeGauge;
    final s = S.of(context);
    final rangeResult = StableRangeCalc.classify(
      value: widget.totalKcalSupplied,
      lower: widget.dailyIntakeLowerKcal,
      upper: widget.dailyIntakeUpperKcal,
    );
    final gaugeValue = StableRangeCalc.progressTowardUpper(
      value: widget.totalKcalSupplied,
      upper: widget.dailyIntakeUpperKcal,
    );
    final displayValue = usesKilojoules
        ? UnitCalc.kcalToKj(widget.totalKcalSupplied)
        : widget.totalKcalSupplied;
    final displayLower = usesKilojoules
        ? UnitCalc.kcalToKj(widget.dailyIntakeLowerKcal)
        : widget.dailyIntakeLowerKcal;
    final displayUpper = usesKilojoules
        ? UnitCalc.kcalToKj(widget.dailyIntakeUpperKcal)
        : widget.dailyIntakeUpperKcal;
    final displayDistance = usesKilojoules
        ? UnitCalc.kcalToKj(rangeResult.distanceToRange)
        : rangeResult.distanceToRange;
    final displayBurned = usesKilojoules
        ? UnitCalc.kcalToKj(widget.totalKcalBurned)
        : widget.totalKcalBurned;
    final unitLabel = usesKilojoules ? s.kjLabel : s.kcalLabel;
    // Profiles without a range keep a single goal, stored as equal bounds.
    final isPointGoal = displayLower.round() == displayUpper.round();
    final rangeLabel = isPointGoal
        ? '${s.goalLabel} ${displayUpper.round()} $unitLabel'
        : '${s.rangeGoalLabel} ${displayLower.round()}–${displayUpper.round()} $unitLabel';
    final left = isPointGoal
        ? '${displayDistance.round()}'
        : '${displayDistance.round()}–${(displayUpper - displayValue).round()}';
    final above = '${displayDistance.round()} $unitLabel';
    // The bar shows its status beside the unit, so it leaves the unit out.
    final barStatusLabel = switch (rangeResult.status) {
      StableRangeStatus.below => s.rangeLeftLabel(left),
      StableRangeStatus.within =>
        isPointGoal ? s.rangeAtGoalLabel : s.rangeWithinLabel,
      StableRangeStatus.above => s.rangeAboveShortLabel(
        '${displayDistance.round()}',
      ),
    };
    final statusLabel = switch (rangeResult.status) {
      StableRangeStatus.below => s.rangeLeftLabel('$left $unitLabel'),
      StableRangeStatus.within =>
        isPointGoal ? s.rangeAtGoalLabel : s.rangeWithinLabel,
      StableRangeStatus.above =>
        isPointGoal
            ? s.rangeAboveGoalLabel(above)
            : s.rangeAboveRangeLabel(above),
    };

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.dashboardItemGap,
        Dimens.spacing16,
        Dimens.dashboardItemGap,
      ),
      child: Column(
        children: [
          AppCard(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              Dimens.spacing24,
              Dimens.spacing20,
              Dimens.spacing24,
              Dimens.spacing24,
            ),
            child: usesRangeGauge
                ? CalorieRangeBar(
                    value: displayValue,
                    lower: displayLower,
                    upper: displayUpper,
                    burned: displayBurned,
                    unitLabel: unitLabel,
                    statusLabel: barStatusLabel,
                  )
                : Column(
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: Dimens.spacing16,
                        runSpacing: Dimens.spacing4,
                        children: [
                          Text(rangeLabel, style: textTheme.labelMedium),
                          Text(
                            '${s.burnedLabel} ${displayBurned.round()} $unitLabel',
                            style: textTheme.labelMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: Dimens.spacing12),
                      Semantics(
                        label:
                            '${displayValue.toInt()} $unitLabel. $rangeLabel. $statusLabel',
                        excludeSemantics: true,
                        child: CircularPercentIndicator(
                          radius: 90,
                          lineWidth: 16,
                          percent: gaugeValue.clamp(0.0, 1.0),
                          animation: true,
                          // From where the arc is, not from empty, when the
                          // day or its total changes.
                          animateFromLastPercent: true,
                          animationDuration: 800,
                          curve: AppMotion.emphasized,
                          circularStrokeCap: CircularStrokeCap.round,
                          backgroundColor: palette.surfaceMuted,
                          progressColor: Theme.of(context).colorScheme.primary,
                          center: SizedBox(
                            width: 136,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedFlipCounter(
                                    duration: const Duration(milliseconds: 800),
                                    curve: AppMotion.emphasized,
                                    value: displayValue.toInt(),
                                    // Tighter than the display ladder (1.12)
                                    // on purpose: a lone hero numeral has no
                                    // second line to lead against, and the
                                    // extra leading only pushes it off-centre
                                    // inside the gauge.
                                    textStyle: textTheme.displaySmall?.copyWith(
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    unitLabel,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: palette.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: Dimens.spacing12),
                      Text(
                        statusLabel,
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: Dimens.dashboardMacroGap),
          Row(
            children: [
              Expanded(
                child: _MacroTile(
                  label: S.of(context).carbsLabel,
                  intake: widget.totalCarbsIntake,
                  goal: widget.totalCarbsGoal,
                  color: palette.carbs,
                  palette: palette,
                ),
              ),
              const SizedBox(width: Dimens.spacing8),
              Expanded(
                child: _MacroTile(
                  label: S.of(context).fatLabel,
                  intake: widget.totalFatsIntake,
                  goal: widget.totalFatsGoal,
                  color: palette.fat,
                  palette: palette,
                ),
              ),
              const SizedBox(width: Dimens.spacing8),
              Expanded(
                child: _MacroTile(
                  label: S.of(context).proteinLabel,
                  intake: widget.totalProteinsIntake,
                  goal: widget.totalProteinsGoal,
                  color: palette.protein,
                  palette: palette,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MacroTile extends StatelessWidget {
  final String label;
  final double intake;
  final double goal;
  final Color color;
  final AppPalette palette;

  const _MacroTile({
    required this.label,
    required this.intake,
    required this.goal,
    required this.color,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pct = (goal <= 0) ? 0.0 : (intake / goal).clamp(0.0, 1.0);
    return AppCard(
      borderRadius: Dimens.radiusM,
      // Narrow side padding and gaps leave room for "555/555 g" on one line
      // at larger text sizes; the bar already carries the macro's colour.
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing12,
        vertical: Dimens.spacing16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OneLine(label, style: textTheme.labelMedium),
          const SizedBox(height: Dimens.spacing12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            // Glides to a new value (another day, a new entry) with the same
            // easing as the calorie bar.
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: pct),
              duration: AppMotion.durationLong,
              curve: AppMotion.standard,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: palette.surfaceMuted,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(height: Dimens.spacing12),
          _OneLine(
            '${intake.toInt()}/${goal.toInt()} g',
            style: textTheme.bodySmall?.copyWith(
              color: palette.textStrong,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps [text] on one line, shrinking it only if the tile is still too narrow.
class _OneLine extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const _OneLine(this.text, {this.style});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(text, style: style, maxLines: 1, softWrap: false),
    );
  }
}
