import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/features/trends/domain/weekly_nutrients.dart';
import 'package:opennutritracker/generated/l10n.dart';

class WeeklyNutrientsCard extends StatelessWidget {
  final WeeklyNutrients summary;
  final Map<String, bool> visibility;
  const WeeklyNutrientsCard({
    super.key,
    required this.summary,
    this.visibility = const {},
  });
  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final dates = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    final numbers = NumberFormat(
      '0.#',
      Localizations.localeOf(context).toString(),
    );
    String label(WeeklyNutrient nutrient) => switch (nutrient) {
      WeeklyNutrient.fiber => s.fiberLabel,
      WeeklyNutrient.sodium => s.sodiumLabel,
      WeeklyNutrient.saturatedFat => s.saturatedFatLabel,
      WeeklyNutrient.sugar => s.sugarLabel,
      WeeklyNutrient.calcium => s.calciumLabel,
      WeeklyNutrient.iron => s.ironLabel,
      WeeklyNutrient.potassium => s.potassiumLabel,
      WeeklyNutrient.vitaminD => s.vitaminDLabel,
      WeeklyNutrient.vitaminB12 => s.vitaminB12Label,
      WeeklyNutrient.magnesium => s.magnesiumLabel,
    };
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.weeklyNutrientsTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${dates.format(summary.start)} \u2013 ${dates.format(summary.end)}',
          ),
          Text(s.weeklyNutrientsDays(summary.loggedDays)),
          const SizedBox(height: 8),
          Text(
            s.weeklyNutrientsExplanation,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (summary.loggedDays == 0) ...[
            const SizedBox(height: 16),
            Text(s.weeklyNutrientsEmpty),
          ] else
            for (final nutrient in WeeklyNutrient.values)
              if (visibility[nutrient.key] != false) ...[
                const Divider(height: 24),
                Text(
                  label(nutrient),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Builder(
                  builder: (context) {
                    final row = summary.nutrients[nutrient]!;
                    final total = row.total == null
                        ? '\u2014'
                        : '${numbers.format(row.total)} ${nutrient.unit}';
                    final average = row.dailyAverage == null
                        ? '\u2014'
                        : '${numbers.format(row.dailyAverage)} ${nutrient.unit}';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.missingFoods > 0
                              ? s.weeklyNutrientsPartialTotal(total)
                              : s.weeklyNutrientsTotal(total),
                        ),
                        Text(s.weeklyNutrientsAverage(average)),
                        if (row.missingFoods > 0)
                          Text(
                            s.weeklyNutrientsMissing(row.missingFoods),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    );
                  },
                ),
              ],
        ],
      ),
    );
  }
}
