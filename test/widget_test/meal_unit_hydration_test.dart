import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_library_item_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

class _AddIntake extends Fake implements AddIntakeUsecase {}

class _Images extends Fake implements CacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => Stream.error(StateError('No image in fixture'));
}

class _AddDay extends Fake implements AddTrackedDayUsecase {}

class _Macros extends Fake implements GetMacroGoalUsecase {}

class _Goal extends Fake implements GetKcalGoalUsecase {
  @override
  Future<double> getKcalGoal({
    UserEntity? userEntity,
    double? totalKcalActivitiesParam,
    double? kcalUserAdjustment,
  }) async => 2000;
}

class _Day extends Fake implements GetTrackedDayUsecase {
  @override
  Future<TrackedDayEntity?> getTrackedDay(DateTime day) async => null;
}

class _Config extends Fake implements ConfigEntity {
  @override
  bool get showMicronutrients => false;
}

class _GetConfig extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => _Config();
}

class _Library extends Fake implements UpdateLibraryItemUsecase {
  @override
  MealEntity? getSavedMeal(MealEntity meal) => null;
}

class _Products extends Fake implements ProductsRepository {
  final result = Completer<MealEntity>();
  @override
  Future<MealEntity> getOFFProductByBarcode(String barcode) => result.future;
}

class _Cache extends Fake implements RemoteSearchCacheDataSource {
  @override
  MealDBO? getDetailedByBarcode(String code) => null;
  @override
  Future<void> cache(MealDBO meal) async {}
}

MealEntity _meal({String? unit, bool detailed = false}) => MealEntity(
  code: 'drink',
  name: 'Drink',
  url: null,
  mealQuantity: null,
  mealUnit: unit,
  servingQuantity: null,
  servingUnit: null,
  servingSize: null,
  nutriments: const MealNutrimentsEntity(
    energyKcal100: 100,
    carbohydrates100: 10,
    fat100: 5,
    proteins100: 5,
    sugars100: 0,
    saturatedFat100: 0,
    fiber100: 0,
  ),
  source: MealSourceEntity.off,
  detailed: detailed,
);

void main() {
  for (final edit in [false, true]) {
    testWidgets('liquid hydration keeps a valid dropdown, user edited: $edit', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final products = _Products();
      final bloc = MealDetailBloc(
        _AddIntake(),
        _AddDay(),
        _Goal(),
        _Macros(),
        _Day(),
        products,
        _Cache(),
      );
      final energy = EnergyUnitProvider();
      locator.registerSingleton<MealDetailBloc>(bloc);
      locator.registerSingleton<CacheManager>(_Images());
      locator.registerSingleton<GetConfigUsecase>(_GetConfig());
      locator.registerSingleton<UpdateLibraryItemUsecase>(_Library());
      addTearDown(() async {
        await locator.reset();
        await bloc.close();
        energy.dispose();
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: energy,
          child: MaterialApp(
            localizationsDelegates: const [S.delegate],
            supportedLocales: S.supportedLocales,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              settings: RouteSettings(
                arguments: MealDetailScreenArguments(
                  _meal(),
                  IntakeTypeEntity.lunch,
                  DateTime(2026, 9, 22),
                  false,
                ),
              ),
              builder: (_) => const MealDetailScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final dropdown = find.byType(DropdownButtonFormField<String>);
      if (edit) {
        tester.widget<DropdownButtonFormField<String>>(dropdown).onChanged!(
          'g',
        );
        await tester.pump();
        await tester.enterText(find.byType(TextFormField).first, '125');
        await tester.pump();
      }
      products.result.complete(_meal(unit: 'ml', detailed: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final field = tester.widget<DropdownButtonFormField<String>>(dropdown);
      expect(field.initialValue, 'ml');
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .items!
            .where((item) => item.value == 'ml'),
        hasLength(1),
      );
      expect(bloc.state.selectedUnit, 'ml');
      expect(bloc.state.totalKcal, edit ? 125 : 100);
      expect(
        double.parse(
          tester
              .widget<TextFormField>(find.byType(TextFormField).first)
              .controller!
              .text,
        ),
        edit ? 125 : 100,
      );

      // Subsequent dependency updates must not restore the thin route snapshot.
      energy.updateUsesKilojoules(true);
      await tester.pumpAndSettle();
      expect(
        tester.widget<DropdownButtonFormField<String>>(dropdown).initialValue,
        'ml',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
