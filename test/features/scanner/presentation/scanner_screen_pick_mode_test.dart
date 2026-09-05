import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/search_product_by_barcode_usecase.dart';
import 'package:opennutritracker/features/scanner/presentation/scanner_bloc.dart';
import 'package:opennutritracker/features/scanner/scanner_screen.dart';

/// Regression cover for GitHub #443: the recipe ingredient picker needs a
/// scanner that hands a [MealEntity] back to its caller rather than routing
/// into the meal-detail logging flow.
void main() {
  group('ScannerScreenArguments', () {
    test('pick() sets pickMode true and leaves logging-flow fields null', () {
      final args = ScannerScreenArguments.pick();

      expect(args.pickMode, isTrue);
      expect(args.day, isNull);
      expect(args.intakeTypeEntity, isNull);
      expect(args.initialBarcode, isNull);
    });

    test('pick(initialBarcode:) carries the barcode through', () {
      final args = ScannerScreenArguments.pick(initialBarcode: '1234567890123');

      expect(args.pickMode, isTrue);
      expect(args.initialBarcode, '1234567890123');
    });

    test('the default constructor still produces a logging-flow args', () {
      final args = ScannerScreenArguments(
        DateTime(2026, 5, 21),
        IntakeTypeEntity.breakfast,
      );

      expect(args.pickMode, isFalse);
      expect(args.day, DateTime(2026, 5, 21));
      expect(args.intakeTypeEntity, IntakeTypeEntity.breakfast);
    });
  });

  group('ScannerScreen pick mode', () {
    final getIt = GetIt.instance;

    setUp(() async {
      if (getIt.isRegistered<ScannerBloc>()) {
        await getIt.unregister<ScannerBloc>();
      }
      // The bloc takes a search usecase that returns the canned meal and a
      // config usecase that yields an unsurprising default. Using the real
      // bloc keeps the state-transition surface honest — the test only
      // stubs the data sources.
      getIt.registerFactory<ScannerBloc>(
        () => ScannerBloc(
          _FakeSearchUseCase(_loadedMeal),
          _FakeGetConfigUsecase(),
        ),
      );
    });

    tearDown(() async {
      if (getIt.isRegistered<ScannerBloc>()) {
        await getIt.unregister<ScannerBloc>();
      }
    });

    testWidgets(
      'pops the loaded MealEntity to its caller after a successful scan',
      (tester) async {
        MealEntity? receivedMeal;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      final result = await Navigator.of(context).push<MealEntity>(
                        MaterialPageRoute(
                          settings: RouteSettings(
                            // initialBarcode triggers ScannerLoadProductEvent
                            // straight from didChangeDependencies, which lets
                            // the test avoid rendering the MobileScanner
                            // camera widget (no platform channel in unit
                            // tests).
                            arguments: ScannerScreenArguments.pick(
                              initialBarcode: '1234567890123',
                            ),
                          ),
                          builder: (_) => const ScannerScreen(),
                        ),
                      );
                      receivedMeal = result;
                    },
                    child: const Text('open scanner'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open scanner'));
        // Give the bloc time to resolve the (synchronous) fake usecase and
        // for the post-build microtask in BlocBuilder to run Navigator.pop.
        await tester.pumpAndSettle();

        expect(receivedMeal, isNotNull);
        expect(receivedMeal!.code, '1234567890123');
        expect(receivedMeal!.name, 'Greek yoghurt');
      },
    );
  });

  group('ScannerScreen logging flow (non-pick)', () {
    final getIt = GetIt.instance;

    setUp(() async {
      if (getIt.isRegistered<ScannerBloc>()) {
        await getIt.unregister<ScannerBloc>();
      }
      getIt.registerFactory<ScannerBloc>(
        () => ScannerBloc(
          _FakeSearchUseCase(_loadedMeal),
          _FakeGetConfigUsecase(),
        ),
      );
    });

    tearDown(() async {
      if (getIt.isRegistered<ScannerBloc>()) {
        await getIt.unregister<ScannerBloc>();
      }
    });

    testWidgets(
      'replaces the scanner with MealDetailScreen carrying day + intake type',
      (tester) async {
        final pushedArgs = <Object?>[];

        await tester.pumpWidget(
          MaterialApp(
            onGenerateRoute: (settings) {
              if (settings.name == NavigationOptions.mealDetailRoute) {
                pushedArgs.add(settings.arguments);
                return MaterialPageRoute(
                  settings: settings,
                  builder: (_) => const Scaffold(body: Text('meal-detail')),
                );
              }
              return null;
            },
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        settings: RouteSettings(
                          arguments: ScannerScreenArguments(
                            DateTime(2026, 5, 21),
                            IntakeTypeEntity.breakfast,
                            initialBarcode: '5449000000996',
                          ),
                        ),
                        builder: (_) => const ScannerScreen(),
                      ),
                    ),
                    child: const Text('open scanner'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open scanner'));
        await tester.pumpAndSettle();

        expect(find.text('meal-detail'), findsOneWidget);
        expect(
          pushedArgs,
          hasLength(1),
          reason: 'scanner should replace itself with meal-detail exactly once',
        );
        final args = pushedArgs.single as MealDetailScreenArguments;
        expect(args.day, DateTime(2026, 5, 21));
        expect(args.intakeTypeEntity, IntakeTypeEntity.breakfast);
        expect(args.mealEntity.code, '1234567890123');
      },
    );
  });
}

final _loadedMeal = MealEntity(
  code: '1234567890123',
  name: 'Greek yoghurt',
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

class _FakeSearchUseCase implements SearchProductByBarcodeUseCase {
  final MealEntity _result;
  _FakeSearchUseCase(this._result);

  @override
  Future<MealEntity> searchProductByBarcode(String barcode) async => _result;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _FakeGetConfigUsecase implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.system);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}
