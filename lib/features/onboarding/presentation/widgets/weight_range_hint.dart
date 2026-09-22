import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/presentation/sources_screen.dart';
import 'package:opennutritracker/core/utils/calc/healthy_weight_calc.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_display_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

class WeightRangeHint extends StatelessWidget {
  final double heightCm;
  final double weightKg;
  final BodyWeightUnit unit;
  final ValueChanged<double> onApply;

  const WeightRangeHint({
    super.key,
    required this.heightCm,
    required this.weightKg,
    required this.unit,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final range = HealthyWeightRange.forHeightCm(heightCm);
    final suggested = range.suggestionFor(weightKg);
    String weight(double value) => formatBodyWeight(
      value,
      unit,
      kgLabel: s.kgLabel,
      lbLabel: s.lbsLabel,
      stLabel: s.stLabel,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.onboardingWeightRangeLabel(
              weight(range.minKg),
              weight(range.maxKg),
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            s.onboardingWeightRangeSource,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Semantics(
                identifier: 'onboarding-target-weight-suggestion',
                child: ActionChip(
                  label: Text(s.onboardingHealthyRangeApply(weight(suggested))),
                  onPressed: () => onApply(suggested),
                ),
              ),
              Semantics(
                identifier: 'onboarding-weight-range-sources',
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SourcesScreen()),
                  ),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text(s.settingsSourcesLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
