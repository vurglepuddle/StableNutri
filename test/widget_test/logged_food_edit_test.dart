import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
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
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/data/repository/products_repository.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../helpers/test_l10n.dart';

class _AddIntake extends Fake implements AddIntakeUsecase {}

class _AddDay extends Fake implements AddTrackedDayUsecase {}

class _Macros extends Fake implements GetMacroGoalUsecase {}

class _Images extends Fake implements CacheManager {}

class _Products extends Fake implements ProductsRepository {}

class _Cache extends Fake implements RemoteSearchCacheDataSource {}

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
  MealEntity? saved;
  final written = <MealEntity>[];

  @override
  MealEntity? getSavedMeal(MealEntity meal) => saved;

  @override
  Future<MealEntity> updateMeal(
    MealEntity meal, {
    required bool favorite,
    required bool rescue,
  }) async {
    final updated = meal.copyWith(isFavorite: favorite, isRescue: rescue);
    written.add(updated);
    return updated;
  }
}

class _Home extends Fake implements HomeBloc {
  final replaced = <(IntakeEntity, IntakeEntity)>[];
  final removed = <IntakeEntity>[];
  final restored = <IntakeEntity>[];

  @override
  Future<void> replaceIntakeItem(
    IntakeEntity old,
    IntakeEntity updated,
  ) async => replaced.add((old, updated));

  @override
  Future<void> deleteIntakeItem(IntakeEntity intake) async =>
      removed.add(intake);

  @override
  Future<void> restoreIntakeItem(IntakeEntity intake) async =>
      restored.add(intake);

  @override
  void add(HomeEvent event) {}
}

final _soup = MealEntity(
  code: 'soup',
  name: 'Pea soup',
  url: null,
  mealQuantity: null,
  mealUnit: 'g',
  servingQuantity: 150,
  servingUnit: 'g',
  servingSize: null,
  nutriments: const MealNutrimentsEntity(
    energyKcal100: 80,
    carbohydrates100: 10,
    fat100: 2,
    proteins100: 5,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceEntity.custom,
);

/// 1.5 servings, logged as 225 g.
final _logged = IntakeEntity(
  id: 'entry',
  unit: 'serving',
  amount: 225,
  type: IntakeTypeEntity.lunch,
  meal: _soup,
  dateTime: DateTime(2026, 9, 24, 13),
);

/// Tapping a logged food opens the food screen on that entry: its amount
/// and meal at the top, and Save or Remove from this day at the bottom.
void main() {
  late _Home home;
  late MealDetailBloc bloc;
  late _Library library;

  Future<void> pumpEntry(
    WidgetTester tester, {
    Size size = const Size(411, 1200),
    double textScale = 1,
    MealEntity? savedInLibrary,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    home = _Home();
    library = _Library()..saved = savedInLibrary;
    bloc = MealDetailBloc(
      _AddIntake(),
      _AddDay(),
      _Goal(),
      _Macros(),
      _Day(),
      _Products(),
      _Cache(),
    );
    final energy = EnergyUnitProvider();
    locator.registerSingleton<MealDetailBloc>(bloc);
    locator.registerSingleton<HomeBloc>(home);
    locator.registerSingleton<CacheManager>(_Images());
    locator.registerSingleton<GetConfigUsecase>(_GetConfig());
    locator.registerSingleton<UpdateLibraryItemUsecase>(library);
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    settings: RouteSettings(
                      arguments: MealDetailScreenArguments(
                        _logged.meal,
                        _logged.type,
                        DateTime(2026, 9, 24),
                        false,
                        loggedIntake: _logged,
                      ),
                    ),
                    builder: (_) => const MealDetailScreen(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  TextField quantity(WidgetTester tester) => tester.widget<TextField>(
    find.descendant(
      of: find.bySemanticsIdentifier('meal-detail-quantity'),
      matching: find.byType(TextField),
    ),
  );

  testWidgets('opens on the logged amount, in servings', (tester) async {
    await pumpEntry(tester);
    expect(quantity(tester).controller!.text, '1.5');
    expect(bloc.state.selectedUnit, 'serving');
    expect(bloc.state.totalKcal, 180);
    expect(find.text(l10nEn.addLabel), findsNothing);
    expect(find.byTooltip(l10nEn.loggedFoodRemove), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving to another meal keeps the exact amount', (tester) async {
    await pumpEntry(tester);
    await tester.tap(find.text(l10nEn.lunchLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nEn.dinnerLabel).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nEn.buttonSaveLabel));
    await tester.pumpAndSettle();

    final (old, updated) = home.replaced.single;
    expect(old, _logged);
    expect(updated.id, 'entry');
    expect(updated.type, IntakeTypeEntity.dinner);
    expect(updated.amount, 225);
    expect(updated.unit, 'serving');
    expect(updated.dateTime, _logged.dateTime);
    expect(find.byType(MealDetailScreen), findsNothing);
  });

  testWidgets('a new amount is saved in grams', (tester) async {
    await pumpEntry(tester);
    await tester.enterText(
      find.descendant(
        of: find.bySemanticsIdentifier('meal-detail-quantity'),
        matching: find.byType(TextField),
      ),
      '2',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nEn.buttonSaveLabel));
    await tester.pumpAndSettle();

    expect(home.replaced.single.$2.amount, 300);
  });

  testWidgets('remove takes it off the day, and undo puts it back', (
    tester,
  ) async {
    await pumpEntry(tester);
    await tester.tap(find.byTooltip(l10nEn.loggedFoodRemove));
    await tester.pumpAndSettle();

    expect(home.removed.single, _logged);
    expect(find.byType(MealDetailScreen), findsNothing);
    expect(find.text(l10nEn.loggedFoodRemoved), findsOneWidget);
    await tester.tap(find.text(l10nEn.loggedFoodUndo));
    await tester.pumpAndSettle();
    expect(home.restored.single, _logged);
  });

  for (final scale in [1.6, 2.0]) {
    testWidgets('fits a 320 px phone at ${scale}x text', (tester) async {
      await pumpEntry(tester, size: const Size(320, 700), textScale: scale);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the Library keeps its own copy of a logged food', (
    tester,
  ) async {
    // Renamed in the Library since it was logged.
    final current = MealEntity(
      code: _soup.code,
      name: 'Green pea soup',
      url: null,
      mealQuantity: null,
      mealUnit: 'g',
      servingQuantity: 300,
      servingUnit: 'g',
      servingSize: null,
      nutriments: _soup.nutriments,
      source: MealSourceEntity.custom,
    );
    await pumpEntry(tester, savedInLibrary: current);
    expect(library.written, isEmpty);
    // The screen still shows the food as it was logged.
    expect(find.text('Pea soup'), findsWidgets);

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();
    expect(library.written.single.name, 'Green pea soup');
    expect(library.written.single.isFavorite, isTrue);
  });

  testWidgets('a double tap on Save changes the day once', (tester) async {
    await pumpEntry(tester);
    await tester.enterText(
      find.descendant(
        of: find.bySemanticsIdentifier('meal-detail-quantity'),
        matching: find.byType(TextField),
      ),
      '2',
    );
    await tester.pump();
    final save = find.text(l10nEn.buttonSaveLabel);
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(home.replaced, hasLength(1));
  });
}
