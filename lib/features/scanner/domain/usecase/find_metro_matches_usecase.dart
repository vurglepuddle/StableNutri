import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/scanner/data/metro_data_source.dart';

/// Finds METRO products that might be the one a scan could not resolve, by
/// the name barcode-list.ru or Open Food Facts gave it. These are guesses:
/// the same line comes in several sizes and fat levels with different
/// values, so the user picks one (or none) — nothing is chosen for them.
class FindMetroMatchesUseCase {
  static const maxMatches = 3;

  final MetroDataSource _metroDataSource;
  final GetConfigUsecase _getConfigUsecase;

  FindMetroMatchesUseCase(this._metroDataSource, this._getConfigUsecase);

  /// Up to [maxMatches] foods, best first, each carrying [barcode] so the
  /// one picked is saved under the code that was scanned. Products without
  /// any nutrition are left out: they are mostly not food ("дружба 230"
  /// also finds a 230 × 220 cm blanket) and would give nothing to fill in.
  Future<List<MealEntity>> find(
    String name, {
    required String barcode,
    String? excludeUrl,
  }) async {
    final config = await _getConfigUsecase.getConfig();
    if (!config.isFoodSourceEnabled(MetroDataSource.sourceCode)) return [];
    if (name.trim().isEmpty) return [];

    final products = await _metroDataSource.searchByName(name);
    final foods = [
      for (final product in products)
        if (product.hasAnyNutrition && product.url != excludeUrl) product,
    ];
    return rank(name, foods)
        .take(maxMatches)
        .map((product) => product.toMealEntity(code: barcode))
        .toList();
  }

  /// METRO's order, nudged by how many words of [name] each product shares
  /// and whether its pack size matches. METRO's search is loose with
  /// abbreviated shop names ("Сыр плав. ванночка Дружба 230гр" finds 680
  /// cheeses), and this lifts the ones that share the distinctive words.
  /// Equal scores keep METRO's order, which also covers names that share no
  /// words at all because METRO transliterated them (Кока-Кола → Coca-Cola).
  static List<MetroProduct> rank(String name, List<MetroProduct> products) {
    final stems = _stems(name);
    final amount = _packAmount(name);
    int score(MetroProduct product) {
      final words = _words(product.name);
      var total = stems
          .where((stem) => words.any((word) => word.startsWith(stem)))
          .length;
      final pack = product.packAmount;
      if (amount != null && pack != null && (pack - amount).abs() < 0.5) {
        total++;
      }
      return total;
    }

    final scored =
        [
          for (var i = 0; i < products.length; i++)
            (product: products[i], score: score(products[i]), order: i),
        ]..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          return byScore != 0 ? byScore : a.order.compareTo(b.order);
        });
    return [for (final entry in scored) entry.product];
  }

  static final _letters = RegExp(r'[a-zа-яё]+');
  static final _latin = RegExp(r'^[a-z]+$');

  /// Words of [text], lower case. Latin words come with a rough Cyrillic
  /// spelling too, because shop names and METRO's write brands either way:
  /// "Кока-Кола" is "Coca-Cola" there, "Натура" is "Natura".
  static List<String> _words(String text) => [
    for (final m in _letters.allMatches(text.toLowerCase())) ...[
      m.group(0)!,
      if (_latin.hasMatch(m.group(0)!)) _cyrillic(m.group(0)!),
    ],
  ];

  static const _toCyrillic = {
    'a': 'а',
    'b': 'б',
    'c': 'к',
    'd': 'д',
    'e': 'е',
    'f': 'ф',
    'g': 'г',
    'h': 'х',
    'i': 'и',
    'j': 'дж',
    'k': 'к',
    'l': 'л',
    'm': 'м',
    'n': 'н',
    'o': 'о',
    'p': 'п',
    'q': 'к',
    'r': 'р',
    's': 'с',
    't': 'т',
    'u': 'у',
    'v': 'в',
    'w': 'в',
    'x': 'кс',
    'y': 'и',
    'z': 'з',
  };

  static String _cyrillic(String latin) =>
      latin.split('').map((c) => _toCyrillic[c] ?? c).join();

  /// Word starts long enough to mean something: "плав." still finds
  /// "плавленый", while "с" and "и" are ignored.
  static Set<String> _stems(String text) => {
    for (final word in _words(text))
      if (word.length >= 3) word.length > 4 ? word.substring(0, 4) : word,
  };

  static final _amountPattern = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(кг|гр|г|мл|л)(?![а-яё])',
    caseSensitive: false,
  );

  /// The pack size written in a shop name, in grams or millilitres:
  /// "230гр" is 230, "0.33 л" is 330.
  static double? _packAmount(String text) {
    final match = _amountPattern.firstMatch(text);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    if (value == null) return null;
    final unit = match.group(2)!.toLowerCase();
    return unit == 'кг' || unit == 'л' ? value * 1000 : value;
  }
}
