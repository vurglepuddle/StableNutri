import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/scanner/data/product_not_found_exception.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/attach_barcode_to_meal_usecase.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/search_product_by_barcode_usecase.dart';
import 'package:opennutritracker/features/scanner/presentation/scanner_bloc.dart';
import 'package:opennutritracker/features/scanner/presentation/widgets/barcode_not_found_view.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Cover for the add-a-barcode flow: a scan that resolves to nothing must
/// land on the not-found screen carrying the code, and both onward paths
/// (create a new item, or connect the code to one the user already has) must
/// keep that code intact.
void main() {
  group('ScannerBloc not-found branch', () {
    test('a ProductNotFoundException emits productNotFound, not a generic '
        'error', () async {
      // Regression: this branch used to read
      // `if (exception == ProductNotFoundException)` inside a bare catch,
      // comparing the caught instance against the Type object. It was never
      // true, so every 404 surfaced as "couldn't fetch product data" and the
      // not-found screen was unreachable.
      final states = await _runToFailure(
        ProductNotFoundException(),
        barcode: '5901234123457',
      );

      expect(states.type, ScannerFailedStateType.productNotFound);
      expect(
        states.barcode,
        '5901234123457',
        reason: 'the not-found screen seeds the create form from this',
      );
    });

    test('any other exception still emits the generic error', () async {
      final failure = await _runToFailure(Exception('socket died'));

      expect(failure.type, ScannerFailedStateType.error);
    });

    test('the failed state carries the unit preference the create form '
        'needs', () async {
      final failure = await _runToFailure(
        ProductNotFoundException(),
        usesImperialFoodUnits: true,
      );

      expect(failure.usesImperialUnits, isTrue);
    });

    test('reset returns to the camera preview state', () async {
      final bloc = ScannerBloc(
        _ThrowingSearchUseCase(ProductNotFoundException()),
        _FakeGetConfigUsecase(),
      );
      addTearDown(bloc.close);

      bloc.add(const ScannerLoadProductEvent(barcode: '5901234123457'));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, isA<ScannerFailedState>());

      bloc.add(const ScannerResetEvent());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, isA<ScannerInitial>());
    });

    test('two failure types are distinguishable states', () {
      // props used to be const-empty, which made every failure state equal to
      // every other one and suppressed the rebuild on a type change.
      expect(
        const ScannerFailedState(
          ScannerFailedStateType.productNotFound,
          barcode: '1',
        ),
        isNot(
          const ScannerFailedState(ScannerFailedStateType.error, barcode: '1'),
        ),
      );
    });
  });

  group('MealEntity.copyWith(code:)', () {
    test('re-points the meal at a new barcode', () {
      final connected = _meal(code: 'old').copyWith(code: '5901234123457');

      expect(connected.code, '5901234123457');
    });

    test('leaves the existing code alone when omitted', () {
      expect(_meal(code: 'old').copyWith(isFavorite: true).code, 'old');
    });
  });

  group('AttachBarcodeToMealUseCase', () {
    test('stamps the code on the meal and saves it to the custom-meal box, '
        'so the next scan of that package resolves locally', () async {
      final dataSource = _RecordingCustomMealDataSource();
      final useCase = AttachBarcodeToMealUseCase(dataSource);

      final connected = await useCase.attachBarcode(
        _meal(code: '0000000000000', name: 'Oat milk'),
        '5901234123457',
      );

      expect(connected.code, '5901234123457');
      expect(dataSource.saved, hasLength(1));
      expect(dataSource.saved.single.code, '5901234123457');
      expect(
        dataSource.saved.single.name,
        'Oat milk',
        reason: 'connecting a code must not re-author the food',
      );
    });

    test(
      'keeps the original source, so provenance and imagery survive',
      () async {
        final dataSource = _RecordingCustomMealDataSource();
        final useCase = AttachBarcodeToMealUseCase(dataSource);

        final connected = await useCase.attachBarcode(
          _meal(code: 'x', name: 'Oat milk'),
          '5901234123457',
        );

        expect(connected.source, MealSourceEntity.off);
        expect(dataSource.saved.single.source, MealSourceDBO.off);
      },
    );
  });

  group('BarcodeNotFoundView', () {
    testWidgets('shows the scanned code and fires each action once', (
      tester,
    ) async {
      var created = 0;
      var connected = 0;
      var scannedAgain = 0;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [S.delegate],
          home: Scaffold(
            body: BarcodeNotFoundView(
              barcode: '5901234123457',
              onCreateItemPressed: () => created++,
              onConnectExistingPressed: () => connected++,
              onScanAgainPressed: () => scannedAgain++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The digits get their own line so a misread is catchable before the
      // user commits to either path.
      expect(find.text('5901234123457'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.tap(find.byIcon(Icons.link_rounded));
      await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded).last);
      await tester.pump();

      expect(created, 1);
      expect(connected, 1);
      expect(scannedAgain, 1);
    });
  });
}

/// Drives the bloc through one failing lookup and returns the failure state.
Future<ScannerFailedState> _runToFailure(
  Object error, {
  String barcode = '5901234123457',
  bool usesImperialFoodUnits = false,
}) async {
  final bloc = ScannerBloc(
    _ThrowingSearchUseCase(error),
    _FakeGetConfigUsecase(usesImperialFoodUnits: usesImperialFoodUnits),
  );
  addTearDown(bloc.close);

  final states = <ScannerState>[];
  final subscription = bloc.stream.listen(states.add);
  bloc.add(ScannerLoadProductEvent(barcode: barcode));
  await Future<void>.delayed(Duration.zero);
  await subscription.cancel();

  return states.whereType<ScannerFailedState>().single;
}

MealEntity _meal({required String? code, String name = 'Test food'}) =>
    MealEntity(
      code: code,
      name: name,
      url: null,
      mealQuantity: '100',
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: null,
      source: MealSourceEntity.off,
      nutriments: const MealNutrimentsEntity(
        energyKcal100: 100,
        carbohydrates100: 4,
        fat100: 5,
        proteins100: 10,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
    );

class _ThrowingSearchUseCase implements SearchProductByBarcodeUseCase {
  final Object _error;

  _ThrowingSearchUseCase(this._error);

  @override
  Future<MealEntity> searchProductByBarcode(String barcode) async =>
      throw _error;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeGetConfigUsecase implements GetConfigUsecase {
  final bool usesImperialFoodUnits;

  _FakeGetConfigUsecase({this.usesImperialFoodUnits = false});

  @override
  Future<ConfigEntity> getConfig() async => ConfigEntity(
    true,
    true,
    false,
    AppThemeEntity.system,
    usesImperialFoodUnits: usesImperialFoodUnits,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _RecordingCustomMealDataSource implements CustomMealDataSource {
  final List<MealDBO> saved = [];

  @override
  Future<void> saveCustomMeal(MealDBO mealDBO) async => saved.add(mealDBO);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}
