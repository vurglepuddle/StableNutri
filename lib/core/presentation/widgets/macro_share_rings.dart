import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

/// Each macro's share of the energy carbs, fat and protein bring (4, 9 and
/// 4 kcal per gram), as whole percentages that add up to exactly 100: the
/// largest remainders are rounded up. All zero when there is no energy.
({int carbs, int fat, int protein}) macroEnergyShares({
  required double carbs,
  required double fat,
  required double protein,
}) {
  double positive(double grams) => grams.isFinite && grams > 0 ? grams : 0;
  final energies = [
    positive(carbs) * 4,
    positive(fat) * 9,
    positive(protein) * 4,
  ];
  final total = energies.fold<double>(0, (sum, value) => sum + value);
  if (total <= 0) return (carbs: 0, fat: 0, protein: 0);
  final exact = [for (final energy in energies) energy / total * 100];
  final shares = [for (final value in exact) value.floor()];
  final byRemainder = [0, 1, 2]
    ..sort((a, b) => (exact[b] - shares[b]).compareTo(exact[a] - shares[a]));
  var missing = 100 - shares.fold<int>(0, (sum, value) => sum + value);
  for (final index in byRemainder) {
    if (missing <= 0) break;
    shares[index]++;
    missing--;
  }
  return (carbs: shares[0], fat: shares[1], protein: shares[2]);
}

/// Three rings for a food: how much of its energy comes from carbs, fat and
/// protein, the percentage inside and the grams underneath.
class MacroShareRings extends StatelessWidget {
  final double carbs;
  final double fat;
  final double protein;

  const MacroShareRings({
    super.key,
    required this.carbs,
    required this.fat,
    required this.protein,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final s = S.of(context);
    final shares = macroEnergyShares(carbs: carbs, fat: fat, protein: protein);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _MacroShareRing(
            share: shares.carbs,
            grams: carbs,
            label: s.carbsLabel,
            color: palette.carbs,
            palette: palette,
          ),
        ),
        Expanded(
          child: _MacroShareRing(
            share: shares.fat,
            grams: fat,
            label: s.fatLabel,
            color: palette.fat,
            palette: palette,
          ),
        ),
        Expanded(
          child: _MacroShareRing(
            share: shares.protein,
            grams: protein,
            label: s.proteinLabel,
            color: palette.protein,
            palette: palette,
          ),
        ),
      ],
    );
  }
}

class _MacroShareRing extends StatelessWidget {
  static const double _radius = 34;
  static const double _lineWidth = 6;

  final int share;
  final double grams;
  final String label;
  final Color color;
  final AppPalette palette;

  const _MacroShareRing({
    required this.share,
    required this.grams,
    required this.label,
    required this.color,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final gramsText = grams.isFinite
        ? '${grams.roundToPrecision(1)}'.replaceFirst(RegExp(r'\.0$'), '')
        : '0';
    // The ring stays one size; its percentage shrinks to fit at large text.
    const inner = (_radius - _lineWidth) * 2 - Dimens.spacing8;
    return MergeSemantics(
      child: Semantics(
        label: S.of(context).macroShareSemantics(label, '$share', gramsText),
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularPercentIndicator(
              radius: _radius,
              lineWidth: _lineWidth,
              percent: share / 100,
              animation: true,
              animateFromLastPercent: true,
              animationDuration: 450,
              curve: Curves.easeOutCubic,
              progressColor: color,
              backgroundColor: palette.surfaceMuted,
              circularStrokeCap: CircularStrokeCap.round,
              center: SizedBox(
                width: inner,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$share%',
                    style: textTheme.titleMedium?.copyWith(
                      color: palette.textStrong,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Dimens.spacing8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: palette.textMuted),
            ),
            Text(
              '$gramsText g',
              textAlign: TextAlign.center,
              style: textTheme.titleSmall?.copyWith(
                color: palette.textStrong,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
