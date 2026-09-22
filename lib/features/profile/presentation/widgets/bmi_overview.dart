import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/user_bmi_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/presentation/widgets/info_dialog.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// BMI as one quiet row the height of a profile tile: the number in a soft
/// accent chip, the category as the title and the risk note as a muted
/// subtitle. Every category uses the same accent, keeping weight feedback
/// neutral rather than warning-coloured. Tapping explains BMI.
class BMIOverview extends StatelessWidget {
  final double bmiValue;
  final UserNutritionalStatus nutritionalStatus;

  const BMIOverview({
    super.key,
    required this.bmiValue,
    required this.nutritionalStatus,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final accent = Theme.of(context).colorScheme.primary;
    final text = Theme.of(context).textTheme;
    final s = S.of(context);
    // Past 1.5x text the words no longer fit beside the chip and would break
    // mid-word, so the chip moves above them.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.5;

    final chip = Container(
      constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
      padding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing8,
        vertical: Dimens.spacing4,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: Dimens.borderRadiusS,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${bmiValue.roundToPrecision(1)}',
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          Text(
            s.bmiLabel,
            style: text.labelSmall?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
    final status = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          nutritionalStatus.getName(context),
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          s.nutritionalStatusRiskLabel(
            nutritionalStatus.getRiskStatus(context),
          ),
          style: text.bodyMedium?.copyWith(color: palette.textMuted),
        ),
      ],
    );
    final help = Icon(
      Icons.help_outline_rounded,
      size: 20,
      color: palette.textMuted,
    );

    // The whole card explains BMI; Sources stays under Settings → About.
    return AppCard(
      onTap: () => showDialog(
        context: context,
        builder: (context) => InfoDialog(title: s.bmiLabel, body: s.bmiInfo),
      ),
      padding: const EdgeInsets.all(Dimens.spacing16),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [chip, const Spacer(), help]),
                const SizedBox(height: Dimens.spacing12),
                status,
              ],
            )
          : Row(
              children: [
                chip,
                const SizedBox(width: Dimens.spacing16),
                Expanded(child: status),
                const SizedBox(width: Dimens.spacing8),
                help,
              ],
            ),
    );
  }
}
