/// Synthetic repeated fruit logs with different weights and household portions.
/// The totals come from one per-100-g food, just as in a Lifesum export.
String lifesumFoodCopiesCsv() {
  final rows = <String>[
    'date,meal_type,title,brand,serving_name,amount,amount_in_grams,'
        'calories,carbs,carbs_fiber,carbs_sugar,cholesterol,fat,'
        'fat_saturated,fat_unsaturated,potassium,protein,sodium',
  ];
  for (var i = 0; i < 10; i++) {
    final grams = 73.0 + i * 17;
    final serving = ['g', 'small', 'medium', 'large'][i % 4];
    final amount = serving == 'g' ? grams : 1.0;
    final totals = [
      51.2,
      12.34,
      2.3,
      8.1,
      0.0,
      0.21,
      0.07,
      0.14,
      0.163,
      1.13,
      0.004,
    ].map((per100) => per100 * grams / 100);
    rows.add(
      [
        '2024-01-${(i + 1).toString().padLeft(2, '0')}',
        'lunch',
        'Nectarine',
        '',
        serving,
        amount,
        grams,
        ...totals,
      ].join(','),
    );
  }
  return rows.join('\n');
}
