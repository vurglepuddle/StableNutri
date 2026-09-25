import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/scanner/data/metro_data_source.dart';
import 'package:opennutritracker/features/scanner/data/product_not_found_exception.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/find_metro_matches_usecase.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/search_product_by_barcode_usecase.dart';
import 'package:opennutritracker/features/scanner/presentation/scanner_bloc.dart';
import 'package:opennutritracker/features/scanner/presentation/widgets/barcode_not_found_view.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../fixture/metro_fixtures.dart';
import '../../helpers/test_l10n.dart';

const _natura = '4601751024794';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Stable',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('MetroDataSource', () {
    MetroProduct first(String answer) => MetroDataSource.parseProduct(
      (jsonDecode(answer)['data']['search']['products']['products'] as List)
              .first
          as Map<String, dynamic>,
    );

    test('reads the four main values and the pack from attributes', () {
      final cheese = first(metroNaturaAnswer);

      expect(cheese.kcal100, 340);
      expect(cheese.protein100, 25);
      expect(cheese.fat100, 26);
      expect(cheese.carbs100, 0);
      expect(cheese.packAmount, 150);
      expect(cheese.hasAllNutrition, isTrue);
      expect(cheese.isLiquid, isFalse);
    });

    test('makes the link absolute and the capitalised maker readable', () {
      final cheese = first(metroNaturaAnswer);

      expect(
        cheese.url,
        'https://online.metro-cc.ru/products/'
        '150g-syr-slivochnyy-45-natura-narezka-bzmzh',
      );
      expect(cheese.brand, 'Natura');
    });

    test('a drink is measured in ml and a decimal comma still parses', () {
      final cola = first(metroColaAnswer);
      final meal = cola.toMealEntity(code: '5449000000996');

      expect(cola.isLiquid, isTrue);
      expect(cola.carbs100, 10.6);
      expect(cola.brand, 'Coca-Cola', reason: 'mixed case is kept');
      expect(meal.mealUnit, 'ml');
      expect(meal.mealQuantity, '330');
      expect(meal.code, '5449000000996');
      expect(meal.backendSource, MetroDataSource.sourceCode);
    });

    test('a weight in the name is not taken for litres', () {
      expect(const MetroProduct(name: 'Сыр Дружба, 150г').isLiquid, isFalse);
      expect(const MetroProduct(name: 'Молоко 3.2%, 1л').isLiquid, isTrue);
      expect(const MetroProduct(name: 'Бальзам 5 лет, 50г').isLiquid, isFalse);
    });

    test(
      'asks by barcode through a GraphQL variable, not pasted text',
      () async {
        late Map<String, dynamic> sent;
        final source = MetroDataSource(
          clientFactory: () => MockClient((request) async {
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            return _json(metroNaturaAnswer);
          }),
        );

        final found = await source.findByBarcode(_natura);

        expect(found.single.name, contains('Natura'));
        expect(sent['variables'], {'code': _natura});
        expect(sent['query'], contains('field: "barcodes"'));
      },
    );

    test('tries again when the connection drops', () async {
      var calls = 0;
      final source = MetroDataSource(
        retryDelay: Duration.zero,
        clientFactory: () => MockClient((request) async {
          calls++;
          if (calls < 3) {
            throw const HandshakeException('Connection terminated');
          }
          return _json(metroNaturaAnswer);
        }),
      );

      expect(await source.findByBarcode(_natura), hasLength(1));
      expect(calls, 3);
    });

    test('does not repeat a request METRO refused', () async {
      var calls = 0;
      final source = MetroDataSource(
        retryDelay: Duration.zero,
        clientFactory: () => MockClient((request) async {
          calls++;
          return http.Response('{"message": ""}', 404);
        }),
      );

      await expectLater(
        source.findByBarcode(_natura),
        throwsA(isA<MetroException>()),
      );
      expect(calls, 1);
    });
  });

  group('SearchProductByBarcodeUseCase with METRO', () {
    late _Off off;
    late _Cache cache;
    late _Metro metro;
    var metroOn = true;

    SearchProductByBarcodeUseCase useCase() => SearchProductByBarcodeUseCase(
      off,
      _NoCustomMeals(),
      cache,
      metroDataSource: metro,
      getConfigUsecase: _Config({MetroDataSource.sourceCode: metroOn}),
    );

    setUp(() {
      off = _Off();
      cache = _Cache();
      metro = _Metro();
      metroOn = true;
    });

    test('an unknown code METRO has in full is a hit, cached for next '
        'time', () async {
      metro.byBarcode = [_cheese()];

      final meal = await useCase().searchProductByBarcode(_natura);

      expect(meal.name, _cheese().name);
      expect(meal.code, _natura);
      expect(meal.nutriments.energyKcal100, 340);
      expect(cache.writes.single.code, _natura);
    });

    test('an Open Food Facts record without values gives way to METRO, '
        'keeping its photo when METRO has none', () async {
      off.result = _offRecord(nutriments: _none);
      metro.byBarcode = [_cheese(images: const [])];

      final meal = await useCase().searchProductByBarcode(_natura);

      expect(meal.backendSource, MetroDataSource.sourceCode);
      expect(meal.thumbnailImageUrl, 'https://off/front.jpg');
    });

    test('an Open Food Facts record with values is used as before', () async {
      off.result = _offRecord(nutriments: _some);

      final meal = await useCase().searchProductByBarcode(_natura);

      expect(meal.source, MealSourceEntity.off);
      expect(metro.barcodeCalls, 0);
    });

    test('without values anywhere, the empty record comes back as the '
        'partial product', () async {
      off.result = _offRecord(nutriments: _none);

      await expectLater(
        useCase().searchProductByBarcode(_natura),
        throwsA(
          isA<ProductNotFoundException>().having(
            (e) => e.partial?.name,
            'partial',
            'Сыр натура сливочный',
          ),
        ),
      );
      expect(cache.writes, isEmpty, reason: 'an empty record is not cached');
    });

    test('a METRO product missing some values becomes the partial', () async {
      metro.byBarcode = [_cheese(fat: null)];

      await expectLater(
        useCase().searchProductByBarcode(_natura),
        throwsA(
          isA<ProductNotFoundException>().having(
            (e) => e.partial?.backendSource,
            'partial source',
            MetroDataSource.sourceCode,
          ),
        ),
      );
    });

    test('a cached empty record does not end the lookup', () async {
      cache.entries.add(MealDBO.fromMealEntity(_offRecord(nutriments: _none)));
      metro.byBarcode = [_cheese()];

      final meal = await useCase().searchProductByBarcode(_natura);

      expect(meal.nutriments.proteins100, 25);
    });

    test('switched off in Settings, METRO is not asked', () async {
      metroOn = false;
      metro.byBarcode = [_cheese()];

      await expectLater(
        useCase().searchProductByBarcode(_natura),
        throwsA(isA<ProductNotFoundException>()),
      );
      expect(metro.barcodeCalls, 0);
    });

    test('METRO failing is a plain not-found, not an error', () async {
      metro.error = MetroException('HTTP 502');

      await expectLater(
        useCase().searchProductByBarcode(_natura),
        throwsA(
          isA<ProductNotFoundException>().having(
            (e) => e.partial,
            'partial',
            isNull,
          ),
        ),
      );
    });
  });

  group('FindMetroMatchesUseCase', () {
    test('only foods, at most three, each under the scanned code', () async {
      final metro = _Metro()
        ..byName = [
          _cheese(name: 'Сыр плавленый Карат дружба 45%, 400г'),
          const MetroProduct(name: 'Плед 230 x 220см', packAmount: 1490),
          _cheese(name: 'Сыр A'),
          _cheese(name: 'Сыр B'),
          _cheese(name: 'Сыр C'),
        ];
      final useCase = FindMetroMatchesUseCase(metro, _Config({}));

      final matches = await useCase.find('сыр дружба', barcode: '460');

      expect(matches, hasLength(FindMetroMatchesUseCase.maxMatches));
      expect(matches.map((m) => m.name), isNot(contains('Плед 230 x 220см')));
      expect(matches.every((m) => m.code == '460'), isTrue);
    });

    test('leaves out the partial product already shown', () async {
      final metro = _Metro()
        ..byName = [
          _cheese(url: 'https://online.metro-cc.ru/products/same'),
          _cheese(name: 'Другой сыр'),
        ];
      final useCase = FindMetroMatchesUseCase(metro, _Config({}));

      final matches = await useCase.find(
        'сыр',
        barcode: '460',
        excludeUrl: 'https://online.metro-cc.ru/products/same',
      );

      expect(matches.single.name, 'Другой сыр');
    });

    test('switched off in Settings, finds nothing', () async {
      final metro = _Metro()..byName = [_cheese()];
      final useCase = FindMetroMatchesUseCase(
        metro,
        _Config({MetroDataSource.sourceCode: false}),
      );

      expect(await useCase.find('сыр', barcode: '460'), isEmpty);
      expect(metro.nameCalls, 0);
    });

    test('shared words lift a product over METRO\'s loose tail', () {
      final ranked =
          FindMetroMatchesUseCase.rank('Сыр плав. ванночка Дружба 230гр', [
            _cheese(name: 'Сыр Natura Сливочный 16%, 150г', pack: 150),
            _cheese(name: 'Сыр плавленый Карат дружба 45%, 400г', pack: 400),
          ]);

      expect(ranked.first.name, contains('дружба'));
    });

    test('Latin brand names match their Cyrillic spelling', () {
      final ranked = FindMetroMatchesUseCase.rank('Кока-Кола ж.б 0.33 л.', [
        _cheese(name: 'Напиток Rich Кола газированный, 330мл', pack: 330),
        _cheese(name: 'Напиток Coca-Cola Original, 330мл', pack: 330),
      ]);

      expect(ranked.first.name, contains('Coca-Cola'));
    });

    test('equal scores keep METRO\'s order', () {
      final ranked = FindMetroMatchesUseCase.rank('чай', [
        _cheese(name: 'Кофе 1'),
        _cheese(name: 'Кофе 2'),
      ]);

      expect(ranked.map((p) => p.name), ['Кофе 1', 'Кофе 2']);
    });
  });

  group('ScannerBloc with METRO', () {
    test('a partial product names the screen and METRO is searched by that '
        'name', () async {
      final partial = _offRecord(nutriments: _none);
      final metro = _Metro()..byName = [_cheese()];
      final bloc = ScannerBloc(
        _NotFound(partial: partial),
        _Config({}),
        findMetroMatchesUseCase: FindMetroMatchesUseCase(metro, _Config({})),
      );
      addTearDown(bloc.close);

      final states = await _failedStates(bloc);

      expect(states.first.suggestedName, 'Сыр натура сливочный');
      expect(states.first.isSearchingMetro, isTrue);
      expect(states.first.partial, partial);
      expect(states.last.isSearchingMetro, isFalse);
      expect(states.last.metroMatches.single.code, _natura);
      expect(metro.lastName, 'Сыр натура сливочный');
    });

    test('with no name to search by, METRO is not asked', () async {
      final metro = _Metro()..byName = [_cheese()];
      final bloc = ScannerBloc(
        _NotFound(),
        _Config({}),
        findMetroMatchesUseCase: FindMetroMatchesUseCase(metro, _Config({})),
      );
      addTearDown(bloc.close);

      final states = await _failedStates(bloc);

      expect(states.last.isSearchingMetro, isFalse);
      expect(states.last.metroMatches, isEmpty);
      expect(metro.nameCalls, 0);
    });
  });

  group('BarcodeNotFoundView with METRO', () {
    Future<void> pump(
      WidgetTester tester, {
      MealEntity? partial,
      bool searching = false,
      List<MealEntity> matches = const [],
      ValueChanged<MealEntity>? onMatch,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [S.delegate],
          home: Scaffold(
            body: BarcodeNotFoundView(
              barcode: _natura,
              suggestedName: partial?.name,
              partial: partial,
              isSearchingMetro: searching,
              metroMatches: matches,
              onMetroMatchPressed: onMatch,
              onCreateItemPressed: () {},
              onConnectExistingPressed: () {},
              onScanAgainPressed: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a product without values says nutrition is missing', (
      tester,
    ) async {
      await pump(tester, partial: _offRecord(nutriments: _none));

      expect(find.text(l10nEn.scannerIncompleteTitle), findsOneWidget);
      expect(
        find.text(l10nEn.scannerPartialSource('Open Food Facts')),
        findsOneWidget,
      );
      expect(find.text(l10nEn.scannerNotFoundTitle), findsNothing);
    });

    testWidgets('says it is searching METRO', (tester) async {
      await pump(tester, searching: true);

      expect(find.text(l10nEn.scannerMetroSearching), findsOneWidget);
    });

    testWidgets('lists the matches with their values and hands back the '
        'one tapped', (tester) async {
      MealEntity? picked;
      final matches = [
        _cheese().toMealEntity(code: _natura),
        _cheese(
          name: 'Сыр без БЖУ',
          kcal: null,
          protein: null,
          fat: null,
          carbs: null,
        ).toMealEntity(code: _natura),
      ];
      await pump(tester, matches: matches, onMatch: (m) => picked = m);

      expect(find.text(l10nEn.scannerMetroMatchesTitle), findsOneWidget);
      expect(find.textContaining('340 kcal'), findsOneWidget);
      expect(
        find.textContaining(l10nEn.scannerMetroNoNutrition),
        findsOneWidget,
      );

      await tester.tap(find.text('Сыр без БЖУ'));
      expect(picked?.name, 'Сыр без БЖУ');
    });
  });
}

http.Response _json(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: {'content-type': 'application/json'},
);

MetroProduct _cheese({
  String name = 'Сыр Natura Сливочный полутвердый нарезка 45%, 150г',
  String? url = 'https://online.metro-cc.ru/products/natura-150',
  List<String> images = const ['https://cdn.metro-cc.ru/natura.png'],
  double? pack = 150,
  double? kcal = 340,
  double? protein = 25,
  double? fat = 26,
  double? carbs = 0,
}) => MetroProduct(
  name: name,
  url: url,
  barcodes: const [_natura],
  brand: 'Natura',
  images: images,
  packAmount: pack,
  kcal100: kcal,
  protein100: protein,
  fat100: fat,
  carbs100: carbs,
);

const _none = MealNutrimentsEntity(
  energyKcal100: null,
  carbohydrates100: null,
  fat100: null,
  proteins100: null,
  sugars100: null,
  saturatedFat100: null,
  fiber100: null,
);

const _some = MealNutrimentsEntity(
  energyKcal100: 260,
  carbohydrates100: null,
  fat100: 16,
  proteins100: 28,
  sugars100: null,
  saturatedFat100: null,
  fiber100: null,
);

MealEntity _offRecord({required MealNutrimentsEntity nutriments}) => MealEntity(
  code: _natura,
  name: 'Сыр натура сливочный',
  brands: 'Натура',
  thumbnailImageUrl: 'https://off/front.jpg',
  mainImageUrl: 'https://off/front.jpg',
  url: 'https://world.openfoodfacts.org/product/$_natura',
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: nutriments,
  source: MealSourceEntity.off,
  detailed: true,
);

Future<List<ScannerFailedState>> _failedStates(ScannerBloc bloc) async {
  final states = <ScannerState>[];
  final subscription = bloc.stream.listen(states.add);
  bloc.add(const ScannerLoadProductEvent(barcode: _natura));
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  await subscription.cancel();
  return states.whereType<ScannerFailedState>().toList();
}

class _Off implements ProductsRepository {
  MealEntity? result;

  @override
  Future<MealEntity> getOFFProductByBarcode(String barcode) async =>
      result ?? (throw ProductNotFoundException());

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _NoCustomMeals implements CustomMealDataSource {
  @override
  List<MealDBO> getAllCustomMeals() => [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Cache implements RemoteSearchCacheDataSource {
  final entries = <MealDBO>[];
  final writes = <MealDBO>[];

  @override
  MealDBO? getDetailedByBarcode(String barcode) => entries
      .where((m) => m.code == barcode && (m.detailed ?? false))
      .firstOrNull;

  @override
  Future<void> cache(MealDBO meal) async => writes.add(meal);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Metro implements MetroDataSource {
  List<MetroProduct> byBarcode = [];
  List<MetroProduct> byName = [];
  Object? error;
  var barcodeCalls = 0;
  var nameCalls = 0;
  String? lastName;

  @override
  Future<List<MetroProduct>> findByBarcode(String barcode) async {
    barcodeCalls++;
    if (error != null) throw error!;
    return byBarcode;
  }

  @override
  Future<List<MetroProduct>> searchByName(String text, {int size = 12}) async {
    nameCalls++;
    lastName = text;
    if (error != null) throw error!;
    return byName;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _NotFound implements SearchProductByBarcodeUseCase {
  final MealEntity? partial;

  _NotFound({this.partial});

  @override
  Future<MealEntity> searchProductByBarcode(String barcode) async =>
      throw ProductNotFoundException(partial: partial);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Config implements GetConfigUsecase {
  final Map<String, bool> toggles;

  _Config(this.toggles);

  @override
  Future<ConfigEntity> getConfig() async => ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.system,
    foodSourceToggles: toggles,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}
