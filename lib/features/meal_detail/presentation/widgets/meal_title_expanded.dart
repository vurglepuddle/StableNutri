import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/meal_value_unit_text.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The meal detail header: the name, then the brand and package quantity as
/// quieter lines. Sized to its content, so long names and larger text wrap
/// instead of being squeezed or clipped.
class MealTitleExpanded extends StatelessWidget {
  final MealEntity meal;
  final bool usesImperialUnits;

  const MealTitleExpanded({
    super.key,
    required this.meal,
    required this.usesImperialUnits,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final text = Theme.of(context).textTheme;
    final brands = meal.brands?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing24,
        Dimens.spacing4,
        Dimens.spacing24,
        Dimens.spacing12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            meal.name ?? '',
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: text.headlineSmall?.copyWith(
              color: palette.textStrong,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (brands.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Dimens.spacing4),
              child: Text(
                brands,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodyLarge?.copyWith(color: palette.textMuted),
              ),
            ),
          // Disclosure for unreviewed machine-translated food names from the
          // backend's translation table.
          if (meal.machineTranslatedName)
            Padding(
              padding: const EdgeInsets.only(top: Dimens.spacing4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.translate_rounded,
                    size: 12,
                    color: palette.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      S.of(context).machineTranslatedNameHint,
                      style: text.labelSmall?.copyWith(
                        color: palette.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (meal.mealQuantity != null)
            Padding(
              padding: const EdgeInsets.only(top: Dimens.spacing4),
              child: MealValueUnitText(
                value: double.tryParse(meal.mealQuantity ?? '') ?? 0,
                meal: meal,
                usesImperialUnits: usesImperialUnits,
                textStyle: text.bodyLarge?.copyWith(color: palette.textMuted),
                prefix: '',
              ),
            ),
        ],
      ),
    );
  }
}
