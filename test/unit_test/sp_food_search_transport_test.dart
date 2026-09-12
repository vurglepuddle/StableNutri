import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/data/data_sources/sp_food_data_source.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sp/sp_const.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Config extends Fake implements ConfigDataSource {
  Map<String, bool>? toggles;

  @override
  Future<Map<String, bool>?> getFoodSourceToggles() async => toggles;
}

void main() {
  late _Config config;
  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;

  const term = 'яблоко & lemon? #42';
  const food = {
    'food_id': 42,
    'source': 'bls',
    'source_code': 'B42',
    'name': 'Apple, raw',
    'energy_kcal_100': 52,
    'serving_gram_weight': 150,
  };

  http.Response rows(List<Map<String, dynamic>> values) => http.Response(
    jsonEncode(values),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Map<String, dynamic> body(int index) =>
      jsonDecode(requests[index].body) as Map<String, dynamic>;

  void expectPrivateTransport() {
    expect(requests, isNotEmpty);
    for (final request in requests) {
      expect(request.method, 'POST');
      expect(request.url.path, startsWith('/rest/v1/rpc/'));
      expect(request.url.query, isEmpty);
      expect(request.url.fragment, isEmpty);
      expect(Uri.decodeFull(request.url.toString()), isNot(contains(term)));
    }
  }

  setUp(() async {
    await locator.reset();
    requests = [];
    config = _Config();
    respond = (_) => rows([]);
    final client = SupabaseClient(
      'https://backend.invalid',
      'synthetic-test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = respond(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    locator.registerSingleton<SupabaseClient>(
      client,
      dispose: (value) => value.dispose(),
    );
    locator.registerSingleton<ConfigDataSource>(config);
  });

  tearDown(() => locator.reset());

  test(
    'English search sends the term in the body and preserves food data',
    () async {
      respond = (_) => rows([food]);

      final result = await SpFoodDataSource().fetchSearchWordResults(
        term,
        localeName: 'en_US',
      );

      expectPrivateTransport();
      expect(requests.single.url.path, '/rest/v1/rpc/search_food_summary');
      expect(body(0), {'term': term, 'sources': null, 'max_rows': 20});
      expect(result.single.name, 'Apple, raw');
      expect(result.single.energyKcal100, 52);
      expect(result.single.servingGramWeight, 150);
    },
  );

  test(
    'localized search keeps matched IDs private and preserves translated names',
    () async {
      config.toggles = {
        for (final code in SPConst.foodSourceDisplayNames.keys)
          code: code == 'bls',
      };
      respond = (request) =>
          request.url.path.endsWith('search_food_translation')
          ? rows([
              {'food_id': 42, 'description': 'Apfel', 'source': 'machine'},
              {'food_id': 43, 'description': 'Birne', 'source': 'native'},
            ])
          : rows([
              food,
              {...food, 'food_id': 43, 'name': 'Pear'},
            ]);

      final result = await SpFoodDataSource().fetchSearchWordResults(
        term,
        localeName: 'de_DE',
      );

      expectPrivateTransport();
      expect(requests, hasLength(2));
      expect(body(0), {'term': term, 'loc': 'de', 'max_rows': 20});
      expect(requests[1].url.path, '/rest/v1/rpc/food_summary_by_ids');
      expect(body(1), {
        'ids': [42, 43],
        'sources': ['bls'],
      });
      expect(result.map((value) => value.displayName), ['Apfel', 'Birne']);
      expect(result.first.displayNameIsMachineTranslated, isTrue);
      expect(result.last.displayNameIsMachineTranslated, isFalse);
    },
  );

  test('an empty localized match falls back to English over POST', () async {
    respond = (request) => request.url.path.endsWith('search_food_summary')
        ? rows([food])
        : rows([]);

    final result = await SpFoodDataSource().fetchSearchWordResults(
      term,
      localeName: 'de_DE',
    );

    expectPrivateTransport();
    expect(requests, hasLength(2));
    expect(requests.last.url.path, '/rest/v1/rpc/search_food_summary');
    expect(body(1)['term'], term);
    expect(result.single.name, 'Apple, raw');
  });

  test('English search sends selected sources in the body', () async {
    config.toggles = {
      for (final code in SPConst.foodSourceDisplayNames.keys)
        code: code == 'bls',
    };

    await SpFoodDataSource().fetchSearchWordResults(term, localeName: 'en_US');

    expectPrivateTransport();
    expect(body(0)['sources'], ['bls']);
  });

  test('disabled sources do not even construct the backend client', () async {
    await locator.unregister<SupabaseClient>();
    locator.registerLazySingleton<SupabaseClient>(
      () => throw StateError('Disabled backend must not initialize'),
    );
    config.toggles = {
      for (final code in SPConst.foodSourceDisplayNames.keys) code: false,
    };

    expect(await SpFoodDataSource().fetchSearchWordResults(term), isEmpty);
    expect(requests, isEmpty);
  });

  test(
    'unconfigured backend skips search without config reads or retries',
    () async {
      await locator.reset();

      expect(await SpFoodDataSource().fetchSearchWordResults(term), isEmpty);
      expect(requests, isEmpty);
    },
  );

  test('blank query makes no request', () async {
    expect(await SpFoodDataSource().fetchSearchWordResults('   '), isEmpty);
    expect(requests, isEmpty);
  });

  test(
    'missing backend functions do not retry or fall back to a GET',
    () async {
      respond = (_) => http.Response(
        jsonEncode({'code': 'PGRST202', 'message': 'Function not found'}),
        404,
        headers: {'content-type': 'application/json'},
      );

      expect(
        await SpFoodDataSource().fetchSearchWordResults(
          term,
          localeName: 'en_US',
        ),
        isEmpty,
      );
      expectPrivateTransport();
      expect(requests, hasLength(1));
    },
  );

  test('transient backend failure still retries and returns results', () async {
    respond = (_) => requests.length == 1
        ? http.Response(
            jsonEncode({'code': '503', 'message': 'Temporarily unavailable'}),
            503,
            headers: {'content-type': 'application/json'},
          )
        : rows([food]);

    final result = await SpFoodDataSource().fetchSearchWordResults(
      term,
      localeName: 'en_US',
    );

    expectPrivateTransport();
    expect(requests, hasLength(2));
    expect(result.single.foodId, 42);
  });
}
