import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/app_const.dart';
import 'package:opennutritracker/core/utils/ont_http_client.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

/// One product from METRO's catalogue, reduced to what a food needs.
class MetroProduct {
  final int? id;
  final String name;
  final String? url;
  final List<String> barcodes;
  final String? brand;
  final List<String> images;

  /// "Вес, объем": the pack's grams or millilitres.
  final double? packAmount;

  /// Per 100 g (per 100 ml for drinks, though METRO labels them "г" too).
  final double? kcal100;
  final double? protein100;
  final double? fat100;
  final double? carbs100;

  const MetroProduct({
    this.id,
    required this.name,
    this.url,
    this.barcodes = const [],
    this.brand,
    this.images = const [],
    this.packAmount,
    this.kcal100,
    this.protein100,
    this.fat100,
    this.carbs100,
  });

  bool get hasAllNutrition =>
      kcal100 != null &&
      protein100 != null &&
      fat100 != null &&
      carbs100 != null;

  bool get hasAnyNutrition =>
      kcal100 != null ||
      protein100 != null ||
      fat100 != null ||
      carbs100 != null;

  /// METRO does not say whether "Вес, объем" is grams or millilitres; the
  /// pack size in the name does ("1л", "330мл"). The lookahead stands in for
  /// a word boundary, which Dart's `\b` only knows for Latin letters.
  bool get isLiquid =>
      RegExp(r'\d\s*(?:мл|л)(?![а-яё])', caseSensitive: false).hasMatch(name);

  /// As a food. [code] replaces METRO's own barcode, so a product the user
  /// picked by name is saved under the barcode they actually scanned.
  MealEntity toMealEntity({String? code}) {
    final unit = isLiquid ? 'ml' : 'g';
    final pack = packAmount;
    return MealEntity(
      code: code ?? (barcodes.isEmpty ? null : barcodes.first),
      name: name,
      brands: brand,
      thumbnailImageUrl: images.isEmpty ? null : images.first,
      mainImageUrl: images.isEmpty ? null : images.first,
      url: url,
      mealQuantity: pack == null
          ? null
          : (pack == pack.roundToDouble() ? pack.toInt().toString() : '$pack'),
      mealUnit: unit,
      servingQuantity: null,
      servingUnit: unit,
      servingSize: null,
      nutriments: MealNutrimentsEntity(
        energyKcal100: kcal100,
        carbohydrates100: carbs100,
        fat100: fat100,
        proteins100: protein100,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      // The "other database" group: the Supabase sources live here too, and
      // [backendSource] names the actual one for labels and links.
      source: MealSourceEntity.fdc,
      backendSource: MetroDataSource.sourceCode,
      detailed: true,
    );
  }
}

/// Reads products from METRO Cash & Carry Russia (online.metro-cc.ru), one of
/// the few Russian shops that publish barcodes and КБЖУ together.
///
/// This is the GraphQL endpoint METRO's own web shop calls; it needs no key.
/// Nutrition sits in free-form product attributes ("Белки, г", …) rather
/// than dedicated fields. See Design/implementation-notes.md for the probe
/// that mapped it.
///
/// METRO's front door drops a share of TLS handshakes from networks it does
/// not like, so each request is tried a few times in quick succession.
class MetroDataSource {
  /// Key in [ConfigEntity.foodSourceToggles] and [MealEntity.backendSource].
  static const sourceCode = 'metro';
  static const displayName = 'METRO';
  static const websiteUrl = 'https://online.metro-cc.ru';

  static final _endpoint = Uri.parse('https://supergraph.metro-cc.ru/graphql');

  /// Any store answers for the whole catalogue; this is the one the
  /// public examples use.
  static const _storeId = 10;

  static const _attempts = 4;
  static const _attemptTimeout = Duration(seconds: 8);

  /// No new attempt starts after this long: past it the user has waited
  /// enough, and the scan moves on without METRO.
  static const _giveUpAfter = Duration(seconds: 12);

  static const _productFields =
      'id name url images barcodes manufacturer { name } '
      'attributes { name text }';

  static const _byBarcodeQuery =
      'query ByBarcode(\$code: String) { search { products('
      'storeId: $_storeId, from: 0, size: 3, showAllActiveProducts: true, '
      'fieldFilters: [{ field: "barcodes", value: \$code }]) '
      '{ products { $_productFields } } } }';

  static const _byTextQuery =
      'query ByText(\$text: String, \$size: Int!) { search(text: \$text) { '
      'products(storeId: $_storeId, from: 0, size: \$size, '
      'showAllActiveProducts: true) { products { $_productFields } } } }';

  final log = Logger('MetroDataSource');

  final http.Client Function() _clientFactory;
  final Duration _retryDelay;

  MetroDataSource({
    http.Client Function()? clientFactory,
    Duration retryDelay = const Duration(milliseconds: 400),
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _retryDelay = retryDelay;

  /// Products carrying exactly [barcode]; usually one or none.
  Future<List<MetroProduct>> findByBarcode(String barcode) =>
      _products(_byBarcodeQuery, {'code': barcode});

  /// METRO's own relevance-ranked text search. It is forgiving — it maps
  /// "Кока-Кола" to "Coca-Cola" — and therefore loose: the tail is noise.
  Future<List<MetroProduct>> searchByName(String text, {int size = 12}) =>
      _products(_byTextQuery, {'text': text, 'size': size});

  Future<List<MetroProduct>> _products(
    String query,
    Map<String, Object> variables,
  ) async {
    final json = await _post(query, variables);
    final products = json['data']?['search']?['products']?['products'];
    if (products is! List) {
      throw MetroException('Unexpected answer: ${json['errors'] ?? json}');
    }
    return [
      for (final product in products)
        if (product is Map<String, dynamic>) parseProduct(product),
    ];
  }

  Future<Map<String, dynamic>> _post(
    String query,
    Map<String, Object> variables,
  ) async {
    final userAgent = await AppConst.getUserAgentString();
    final body = jsonEncode({'query': query, 'variables': variables});
    final elapsed = Stopwatch()..start();
    Object? lastError;
    for (var attempt = 1; attempt <= _attempts; attempt++) {
      if (attempt > 1 && elapsed.elapsed > _giveUpAfter) break;
      final inner = _clientFactory();
      final client = ONTHttpClient(userAgent, inner);
      try {
        final response = await client
            .post(
              _endpoint,
              headers: const {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(_attemptTimeout);
        if (response.statusCode == 200) {
          return jsonDecode(utf8.decode(response.bodyBytes))
              as Map<String, dynamic>;
        }
        lastError = MetroException('HTTP ${response.statusCode}');
        // A 4xx is an answer, not a dropped connection; asking again
        // will not change it.
        if (response.statusCode < 500) break;
      } catch (error) {
        lastError = error;
      } finally {
        inner.close();
      }
      if (attempt < _attempts) await Future.delayed(_retryDelay * attempt);
    }
    log.warning('METRO request failed: $lastError');
    throw lastError is MetroException
        ? lastError
        : MetroException('$lastError');
  }

  static const _kcal = 'Энергетическая ценность, ккал/100 г';
  static const _protein = 'Белки, г';
  static const _fat = 'Жиры, г';
  static const _carbs = 'Углеводы, г';
  static const _pack = 'Вес, объем';

  static MetroProduct parseProduct(Map<String, dynamic> json) {
    final attributes = <String, String>{
      for (final attribute in (json['attributes'] as List? ?? const []))
        if (attribute is Map &&
            attribute['name'] is String &&
            attribute['text'] is String)
          attribute['name'] as String: attribute['text'] as String,
    };
    double? number(String key) {
      final text = attributes[key]?.replaceAll(',', '.').trim();
      return text == null ? null : double.tryParse(text);
    }

    final url = json['url'] as String?;
    final manufacturer = json['manufacturer'];
    return MetroProduct(
      id: json['id'] as int?,
      name: (json['name'] as String? ?? '').trim(),
      url: url == null || url.startsWith('http') ? url : '$websiteUrl$url',
      barcodes: [
        for (final code in (json['barcodes'] as List? ?? const []))
          if (code is String) code,
      ],
      brand: _brandCase(
        manufacturer is Map ? manufacturer['name'] as String? : null,
      ),
      images: [
        for (final image in (json['images'] as List? ?? const []))
          if (image is String) image,
      ],
      packAmount: number(_pack),
      kcal100: number(_kcal),
      protein100: number(_protein),
      fat100: number(_fat),
      carbs100: number(_carbs),
    );
  }

  /// METRO spells makers in capitals ("РУССКОЕ МОРЕ"); a brand field reads
  /// better as "Русское Море". Mixed-case names are left as they are.
  static String? _brandCase(String? brand) {
    final trimmed = brand?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed != trimmed.toUpperCase()) return trimmed;
    return trimmed
        .toLowerCase()
        .split(' ')
        .map(
          (word) =>
              word.isEmpty ? word : word[0].toUpperCase() + word.substring(1),
        )
        .join(' ');
  }
}

class MetroException implements Exception {
  final String message;

  MetroException(this.message);

  @override
  String toString() => 'MetroException: $message';
}
