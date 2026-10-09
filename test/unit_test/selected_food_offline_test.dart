import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/search_product_by_barcode_usecase.dart';

import '../helpers/fake_hive_db_provider.dart';
import '../helpers/hive_test_setup.dart';

class _AddIntake extends Fake implements AddIntakeUsecase {}

class _AddDay extends Fake implements AddTrackedDayUsecase {}

class _Goal extends Fake implements GetKcalGoalUsecase {}

class _Macros extends Fake implements GetMacroGoalUsecase {}

class _Day extends Fake implements GetTrackedDayUsecase {}

class _Products extends Fake implements ProductsRepository {
  final result = Completer<MealEntity>();
  int calls = 0;

  @override
  Future<MealEntity> getOFFProductByBarcode(String barcode) {
    calls++;
    return result.future;
  }
}

class _EmptyCache extends Fake implements RemoteSearchCacheDataSource {
  @override
  MealDBO? getDetailedByBarcode(String barcode) => null;

  @override
  Future<void> cache(MealDBO meal) async {}
}

MealEntity food({bool detailed = false, double kcal = 250}) => MealEntity(
  code: '4000000000000',
  name: 'Bread',
  url: null,
  mealQuantity: '500',
  mealUnit: 'g',
  servingQuantity: detailed ? 25 : null,
  servingUnit: 'g',
  servingSize: detailed ? '1 slice (25 g)' : null,
  nutriments: MealNutrimentsEntity(
    energyKcal100: kcal,
    carbohydrates100: 45,
    fat100: 3,
    proteins100: 9,
    sugars100: null,
    saturatedFat100: null,
    fiber100: detailed ? 6 : null,
  ),
  source: MealSourceEntity.off,
  detailed: detailed,
);

void main() {
  late Directory directory;
  late Box<MealDBO> box;
  late FakeHiveDBProvider db;
  late CustomMealDataSource saved;
  late _Products products;
  late MealDetailBloc bloc;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerHiveAdaptersOnce();
    directory = await Directory.systemTemp.createTemp('stable_offline_food_');
    box = await Hive.openBox<MealDBO>('saved', path: directory.path);
    db = FakeHiveDBProvider(customMealBox: box);
    saved = CustomMealDataSource(db);
    products = _Products();
    bloc = MealDetailBloc(
      _AddIntake(),
      _AddDay(),
      _Goal(),
      _Macros(),
      _Day(),
      products,
      _EmptyCache(),
      customMealDataSource: saved,
    );
  });

  tearDown(() async {
    await bloc.close();
    await box.close();
    await directory.delete(recursive: true);
  });

  test(
    'selection retains full nutrition across restart with an empty cache',
    () async {
      final hydrated = bloc.stream.firstWhere(
        (state) => state.hydratedMeal != null,
      );
      products.result.complete(food(detailed: true));
      bloc.add(HydrateMealEvent(food()));
      await hydrated;
      expect(box.values.single.detailed, isTrue);
      expect(box.values.single.nutriments.fiber100, 6);

      await box.close();
      box = await Hive.openBox<MealDBO>('saved', path: directory.path);
      final reopened = CustomMealDataSource(
        FakeHiveDBProvider(customMealBox: box),
      );
      final offlineProducts = _Products();
      final scanned = await SearchProductByBarcodeUseCase(
        offlineProducts,
        reopened,
        _EmptyCache(),
      ).searchProductByBarcode('4000000000000');
      expect(scanned.servingQuantity, 25);
      expect(scanned.nutriments.fiber100, 6);
      expect(offlineProducts.calls, 0);
    },
  );

  test(
    'an offline hydration failure retains the selected thin nutrition',
    () async {
      final finished = bloc.stream.firstWhere((state) => !state.isHydrating);
      // Handle the failure while it waits for the hydration event to start.
      products.result.future.ignore();
      products.result.completeError(StateError('offline'));
      bloc.add(HydrateMealEvent(food()));
      await finished;
      expect(box.values.single.nutriments.energyKcal100, 250);
      expect(box.values.single.detailed, isFalse);
    },
  );

  test('a saved correction wins over downloads and keeps its labels', () async {
    await saved.saveCustomMeal(
      MealDBO.fromMealEntity(
        food(
          detailed: true,
          kcal: 240,
        ).copyWith(isFavorite: true, isRescue: true),
      ),
    );
    final hydrated = bloc.stream.firstWhere(
      (state) => state.hydratedMeal != null,
    );
    bloc.add(HydrateMealEvent(food(detailed: true)));
    final state = await hydrated;
    expect(state.hydratedMeal!.nutriments.energyKcal100, 240);
    expect(products.calls, 0);
    expect(box.values.single.isFavorite, isTrue);
    expect(box.values.single.isRescue, isTrue);
    expect(box.length, 1);
  });

  test(
    'full hydration upgrades a thin snapshot and preserves labels',
    () async {
      await saved.saveRemoteMealForOffline(food().copyWith(isFavorite: true));
      await saved.saveRemoteMealForOffline(food(detailed: true));
      await saved.saveRemoteMealForOffline(food());
      expect(box.length, 1);
      expect(box.values.single.detailed, isTrue);
      expect(box.values.single.isFavorite, isTrue);
      expect(box.values.single.servingQuantity, 25);
    },
  );

  test(
    'a hydration completing after profile switch cannot save to that profile',
    () async {
      final loading = bloc.stream.firstWhere((state) => state.isHydrating);
      bloc.add(HydrateMealEvent(food()));
      await loading;
      db.simulateProfileSwitch(profileId: 'second', generation: 1);
      final finished = bloc.stream.firstWhere((state) => !state.isHydrating);
      products.result.complete(food(detailed: true));
      await finished;
      expect(box.values.single.detailed, isFalse);
      expect(bloc.state.hydratedMeal, isNull);
    },
  );
}
