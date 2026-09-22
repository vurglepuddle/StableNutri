import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_library_item_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/thumbnail_image.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../helpers/test_l10n.dart';

class _AddIntake extends Fake implements AddIntakeUsecase {}

class _AddDay extends Fake implements AddTrackedDayUsecase {}

class _Macros extends Fake implements GetMacroGoalUsecase {}

class _Images extends Fake implements CacheManager {}

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

/// Hydration returns the same product, so the screen settles.
class _Products extends Fake implements ProductsRepository {
  _Products(this.meal);

  final MealEntity meal;

  @override
  Future<MealEntity> getOFFProductByBarcode(String barcode) async => meal;
}

class _Cache extends Fake implements RemoteSearchCacheDataSource {
  @override
  MealDBO? getDetailedByBarcode(String code) => null;
  @override
  Future<void> cache(MealDBO meal) async {}
}

MealEntity _meal({String name = 'Steam sweet potato', String? brands}) =>
    MealEntity(
      code: 'potato',
      name: name,
      brands: brands,
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: null,
      servingSize: null,
      nutriments: const MealNutrimentsEntity(
        energyKcal100: 86,
        carbohydrates100: 20,
        fat100: 0.1,
        proteins100: 1.6,
        sugars100: 4,
        saturatedFat100: 0,
        fiber100: 3,
      ),
      source: MealSourceEntity.off,
      detailed: true,
    );

/// The add-food screen's header sizes itself to the product: no empty frame
/// without a photo, the brand on its own line, and the Open Food Facts
/// notice behind a small (?) instead of a paragraph.
void main() {
  Future<void> pumpDetail(
    WidgetTester tester,
    MealEntity meal, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bloc = MealDetailBloc(
      _AddIntake(),
      _AddDay(),
      _Goal(),
      _Macros(),
      _Day(),
      _Products(meal),
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            settings: RouteSettings(
              arguments: MealDetailScreenArguments(
                meal,
                IntakeTypeEntity.lunch,
                DateTime(2026, 9, 23),
                false,
              ),
            ),
            builder: (_) => const MealDetailScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a product without a photo shows no image frame', (tester) async {
    await pumpDetail(tester, _meal(brands: 'Homemade'));

    expect(find.byType(ThumbnailImage), findsNothing);
    expect(find.text('Homemade'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Open Food Facts notice opens from a small (?)', (
    tester,
  ) async {
    await pumpDetail(tester, _meal());

    expect(find.text(l10nEn.offDisclaimer), findsNothing);
    // Scrolled to the end, the last row clears the bottom sheet.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Food Facts'));
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.offDisclaimer), findsOneWidget);
  });

  testWidgets('a long name and brand fit at 2x text', (tester) async {
    await pumpDetail(
      tester,
      _meal(
        name: 'Steamed sweet potato with rosemary and a little olive oil',
        brands: 'Homemade, from the farmers market',
      ),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Homemade, from the farmers market'), findsOneWidget);
  });
}
