import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/scanner/data/barcode_list_data_source.dart';
import 'package:opennutritracker/features/scanner/data/product_not_found_exception.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/look_up_barcode_name_usecase.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/search_product_by_barcode_usecase.dart';
import 'package:opennutritracker/features/scanner/presentation/scanner_bloc.dart';
import 'package:opennutritracker/features/scanner/presentation/widgets/barcode_not_found_view.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../fixture/barcode_list_fixtures.dart';
import '../../helpers/test_l10n.dart';

const _cheese = '4600493500023';

void main() {
  group('BarcodeListDataSource.parse', () {
    test('takes the best name from the page title, in normal case', () {
      final result = BarcodeListDataSource.parse(_cheese, barcodeListFoundPage);

      expect(result, isNotNull);
      expect(result!.bestName, 'Сыр плав. ванночка Дружба 230гр');
    });

    test('keeps every variant for this code, most voted first, and skips '
        'rows for other codes', () {
      final result = BarcodeListDataSource.parse(
        _cheese,
        barcodeListFoundPage,
      )!;

      expect(result.variants.map((v) => v.name), [
        'СЫР ПЛАВ. ВАННОЧКА ДРУЖБА 230ГР',
        'СЫР ПЛАВЛЕННЫЙ ДРУЖБА 55% П/К 230Г',
        'СЫР ПЛАВЛЕНЫЙ ДРУЖБА 230Г "КАРАТ"',
        'СЫР "ДРУЖБА" 230 Г',
      ]);
      expect(result.variants.map((v) => v.rating), [4, 4, 3, 1]);
      expect(result.variants.first.unit, 'ШТ.');
    });

    test('an unknown code has no result', () {
      expect(
        BarcodeListDataSource.parse('4600605000170', barcodeListNotFoundPage),
        isNull,
      );
    });

    test('falls back to the top variant when the title has no name', () {
      final untitled = barcodeListFoundPage.replaceFirst(
        RegExp('<title>.*</title>'),
        '<title>Поиск:$_cheese</title>',
      );

      expect(
        BarcodeListDataSource.parse(_cheese, untitled)!.bestName,
        'СЫР ПЛАВ. ВАННОЧКА ДРУЖБА 230ГР',
      );
    });

    test('a UPC-A scan matches the site\'s zero-padded EAN-13', () {
      final padded = barcodeListFoundPage.replaceAll(_cheese, '0012345678905');

      expect(
        BarcodeListDataSource.parse('012345678905', padded)?.variants,
        hasLength(4),
      );
    });
  });

  group('LookUpBarcodeNameUseCase', () {
    test('asks barcode-list.ru while the source is on (the default)', () async {
      final source = _FakeBarcodeListDataSource(_result);
      final useCase = LookUpBarcodeNameUseCase(source, _FakeConfig({}));

      expect((await useCase.lookUp(_cheese))?.bestName, 'Дружба');
      expect(source.calls, [_cheese]);
    });

    test('does not contact the site when switched off in Settings', () async {
      final source = _FakeBarcodeListDataSource(_result);
      final useCase = LookUpBarcodeNameUseCase(
        source,
        _FakeConfig({BarcodeListDataSource.sourceCode: false}),
      );

      expect(await useCase.lookUp(_cheese), isNull);
      expect(source.calls, isEmpty);
    });
  });

  group('ScannerBloc name lookup', () {
    test('shows not-found at once, then fills in the name', () async {
      final states = await _notFoundStates(_FakeLookUp(result: _result));

      expect(states, hasLength(2));
      expect(states.first.isLookingUpName, isTrue);
      expect(states.first.suggestedName, isNull);
      expect(states.last.isLookingUpName, isFalse);
      expect(states.last.suggestedName, 'Дружба');
      expect(states.last.barcode, _cheese);
    });

    test('an unknown code ends the lookup without a name', () async {
      final states = await _notFoundStates(_FakeLookUp());

      expect(states.last.isLookingUpName, isFalse);
      expect(states.last.suggestedName, isNull);
    });

    test('a failing lookup still leaves the not-found screen usable', () async {
      final states = await _notFoundStates(_FakeLookUp(error: Exception('x')));

      expect(
        states.last.type,
        ScannerFailedStateType.productNotFound,
        reason: 'the name is a bonus; the create/connect flow must survive',
      );
      expect(states.last.isLookingUpName, isFalse);
    });
  });

  group('BarcodeNotFoundView name', () {
    testWidgets('says it is looking the name up', (tester) async {
      await _pumpView(tester, isLookingUpName: true);

      expect(find.text(l10nEn.scannerNameLookupPending), findsOneWidget);
    });

    testWidgets('shows the suggested name and where it came from', (
      tester,
    ) async {
      await _pumpView(tester, suggestedName: 'Сыр Дружба 230 г');

      expect(find.text('Сыр Дружба 230 г'), findsOneWidget);
      expect(find.text(l10nEn.scannerSuggestedNameSource), findsOneWidget);
      expect(find.text(l10nEn.scannerNameLookupPending), findsNothing);
    });
  });
}

const _result = BarcodeListResult(_cheese, 'Дружба', [
  BarcodeListName('ДРУЖБА', 'ШТ.', 4),
]);

Future<List<ScannerFailedState>> _notFoundStates(
  LookUpBarcodeNameUseCase lookUp,
) async {
  final bloc = ScannerBloc(
    _NotFoundSearch(),
    _FakeConfig({}),
    lookUpBarcodeNameUseCase: lookUp,
  );
  addTearDown(bloc.close);

  final states = <ScannerState>[];
  final subscription = bloc.stream.listen(states.add);
  bloc.add(const ScannerLoadProductEvent(barcode: _cheese));
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await subscription.cancel();
  return states.whereType<ScannerFailedState>().toList();
}

Future<void> _pumpView(
  WidgetTester tester, {
  String? suggestedName,
  bool isLookingUpName = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [S.delegate],
      home: Scaffold(
        body: BarcodeNotFoundView(
          barcode: _cheese,
          suggestedName: suggestedName,
          isLookingUpName: isLookingUpName,
          onCreateItemPressed: () {},
          onConnectExistingPressed: () {},
          onScanAgainPressed: () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

class _NotFoundSearch implements SearchProductByBarcodeUseCase {
  @override
  Future<MealEntity> searchProductByBarcode(
    String barcode, {
    ValueChanged<BarcodeLookupStage>? onStage,
  }) async => throw ProductNotFoundException();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeLookUp implements LookUpBarcodeNameUseCase {
  final BarcodeListResult? result;
  final Object? error;

  _FakeLookUp({this.result, this.error});

  @override
  Future<BarcodeListResult?> lookUp(String barcode) async {
    if (error != null) throw error!;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeBarcodeListDataSource implements BarcodeListDataSource {
  final BarcodeListResult? result;
  final calls = <String>[];

  _FakeBarcodeListDataSource(this.result);

  @override
  Future<BarcodeListResult?> lookUp(String barcode) async {
    calls.add(barcode);
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeConfig implements GetConfigUsecase {
  final Map<String, bool> toggles;

  _FakeConfig(this.toggles);

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
