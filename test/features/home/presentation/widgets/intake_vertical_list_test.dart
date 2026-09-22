import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/core/utils/vertical_list_popup_menu_selections.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/home/presentation/widgets/intake_vertical_list.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';
import '../../../../helpers/test_l10n.dart';
import '../../../../helpers/font_loading.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/usecase/compute_recipe_nutrition_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/save_recipe_usecase.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipe_builder_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/bloc/recipes_bloc.dart';
import 'package:opennutritracker/features/recipes/presentation/screens/recipe_builder_screen.dart';

class _RecipeRepository extends Fake implements RecipeRepository {
  final saved = <RecipeEntity>[];
  @override
  Future<void> saveRecipe(RecipeEntity recipe) async => saved.add(recipe);
}

class _RecipesBloc extends Fake implements RecipesBloc {
  int refreshes = 0;
  @override
  void add(RecipesEvent event) => refreshes++;
}

class _FakeMealDetailBloc extends Fake implements MealDetailBloc {}

class _FakeHomeBloc extends Fake implements HomeBloc {}

/// Single-profile stub: with only one profile the "Copy to profile" menu
/// item stays hidden, so the section menu matches its pre-multi-profile
/// shape in these tests.
class _SingleProfileGetProfilesUsecase implements GetProfilesUsecase {
  static final _profile = ProfileEntity(
    id: 'p1',
    name: 'Me',
    createdAt: DateTime(2026, 1, 1),
    boxSuffix: '',
  );

  @override
  List<ProfileEntity> getProfiles() => [_profile];

  @override
  String get activeProfileId => 'p1';

  @override
  ProfileEntity? getActiveProfile() => _profile;
}

IntakeEntity _buildIntake({
  required double amount,
  required double kcal100,
  required double carbs100,
  required double fat100,
  required double protein100,
}) {
  return IntakeEntity(
    id: 'test-intake',
    unit: 'g',
    amount: amount,
    type: IntakeTypeEntity.breakfast,
    dateTime: DateTime(2026, 1, 1),
    meal: MealEntity(
      code: 'test-meal',
      name: 'Test Meal',
      url: null,
      mealQuantity: '100',
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: '100 g',
      nutriments: MealNutrimentsEntity(
        energyKcal100: kcal100,
        carbohydrates100: carbs100,
        fat100: fat100,
        proteins100: protein100,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceEntity.custom,
    ),
  );
}

Widget _wrapWithMaterial(Widget child, {double scale = 1}) {
  return ChangeNotifierProvider<EnergyUnitProvider>(
    create: (_) => EnergyUnitProvider(),
    child: MaterialApp(
      theme: ThemeData(fontFamily: 'Commissioner'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      routes: {
        NavigationOptions.recipeBuilderRoute: (_) =>
            const RecipeBuilderScreen(),
      },
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUpAll(() async {
    await loadAppFont();
    final locator = GetIt.instance;
    locator.registerFactory<MealDetailBloc>(_FakeMealDetailBloc.new);
    locator.registerFactory<HomeBloc>(_FakeHomeBloc.new);
    locator.registerFactory<GetProfilesUsecase>(
      _SingleProfileGetProfilesUsecase.new,
    );
  });

  tearDownAll(() {
    GetIt.instance.reset();
  });

  // 100 g intake of food with 200 kcal/100g, 20 g carbs/100g, 10 g fat/100g, 5 g protein/100g
  // → totals: 200 kcal, 20 g C, 10 g F, 5 g P
  final intakes = [
    _buildIntake(
      amount: 100,
      kcal100: 200,
      carbs100: 20,
      fat100: 10,
      protein100: 5,
    ),
  ];

  String headerWithMacros() =>
      '200 ${l10nEn.kcalLabel}\n'
      '20 ${l10nEn.carbsLabelShort}  '
      '10 ${l10nEn.fatLabelShort}  '
      '5 ${l10nEn.proteinLabelShort}';

  String headerKcalOnly() => '200 ${l10nEn.kcalLabel}';

  testWidgets(
    'Dinner stays on one line with summary and both menus at 320 px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _wrapWithMaterial(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: SingleChildScrollView(
              child: IntakeVerticalList(
                day: DateTime(2026, 1, 1),
                title: 'Dinner',
                listIcon: Icons.dinner_dining,
                addMealType: AddMealType.dinnerType,
                intakeList: intakes,
                usesImperialUnits: false,
                mealKcalTarget: 12345,
                onSortTypeChanged: (_) {},
                onDeleteIntakeCallback: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(find.text('Dinner'));
      expect(title.maxLines, 1);
      final paragraph = tester.renderObject<RenderBox>(find.text('Dinner'));
      expect(paragraph.size.width, greaterThan(90));
    },
  );

  testWidgets('shows kcal + macro breakdown when showMealMacros is true', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrapWithMaterial(
        IntakeVerticalList(
          day: DateTime(2026, 1, 1),
          title: 'Breakfast',
          listIcon: Icons.bakery_dining_outlined,
          addMealType: AddMealType.breakfastType,
          intakeList: intakes,
          usesImperialUnits: false,
          showMealMacros: true,
          onDeleteIntakeCallback: (_, _) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text(headerWithMacros()), findsOneWidget);
  });

  testWidgets('shows only kcal when showMealMacros is false', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrapWithMaterial(
        IntakeVerticalList(
          day: DateTime(2026, 1, 1),
          title: 'Breakfast',
          listIcon: Icons.bakery_dining_outlined,
          addMealType: AddMealType.breakfastType,
          intakeList: intakes,
          usesImperialUnits: false,
          showMealMacros: false,
          onDeleteIntakeCallback: (_, _) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text(headerWithMacros()), findsNothing);
  });

  testWidgets(
    'defaults to showing macro breakdown when showMealMacros is omitted',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrapWithMaterial(
          IntakeVerticalList(
            day: DateTime(2026, 1, 1),
            title: 'Breakfast',
            listIcon: Icons.bakery_dining_outlined,
            addMealType: AddMealType.breakfastType,
            intakeList: intakes,
            usesImperialUnits: false,
            onDeleteIntakeCallback: (_, _) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text(headerWithMacros()), findsOneWidget);
    },
  );

  testWidgets('shows no header text when intake list is empty', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrapWithMaterial(
        IntakeVerticalList(
          day: DateTime(2026, 1, 1),
          title: 'Breakfast',
          listIcon: Icons.bakery_dining_outlined,
          addMealType: AddMealType.breakfastType,
          intakeList: const [],
          usesImperialUnits: false,
          showMealMacros: true,
          onDeleteIntakeCallback: (_, _) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text(headerWithMacros()), findsNothing);
    expect(find.text(headerKcalOnly()), findsNothing);
  });

  // Regression: the QR-share/import options were dropped from the popup
  // menu when the macros toggle PR landed on a stale base. Lock in the
  // expected items so it can't happen again silently.
  testWidgets(
    'popup menu shows Copy/Delete/Share/Import for non-empty section',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrapWithMaterial(
          IntakeVerticalList(
            day: DateTime(2026, 1, 1),
            title: 'Breakfast',
            listIcon: Icons.bakery_dining_outlined,
            addMealType: AddMealType.breakfastType,
            intakeList: intakes,
            usesImperialUnits: false,
            showMealMacros: true,
            onCopyIntakeCallback: (_, _, _) {},
            onDeleteIntakeCallback: (_, _) {},
          ),
        ),
      );
      await tester.pump();

      await tester.tap(
        find.byType(PopupMenuButton<VerticalListPopupMenuSelections>),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.dialogCopyLabel), findsOneWidget);
      expect(find.text(l10nEn.deleteAllLabel), findsOneWidget);
      expect(find.text(l10nEn.shareMealLabel), findsOneWidget);
      expect(find.text(l10nEn.importMealLabel), findsOneWidget);
      expect(find.text(l10nEn.saveMealAsRecipeLabel), findsOneWidget);
    },
  );

  testWidgets('popup menu shows only Import when section is empty', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrapWithMaterial(
        IntakeVerticalList(
          day: DateTime(2026, 1, 1),
          title: 'Breakfast',
          listIcon: Icons.bakery_dining_outlined,
          addMealType: AddMealType.breakfastType,
          intakeList: const [],
          usesImperialUnits: false,
          showMealMacros: true,
          onDeleteIntakeCallback: (_, _) {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byType(PopupMenuButton<VerticalListPopupMenuSelections>),
    );
    await tester.pumpAndSettle();

    // Empty section: no Copy/Delete/Share — nothing to act on. Import is
    // always available so the user can scan a QR to populate the section.
    expect(find.text(l10nEn.dialogCopyLabel), findsNothing);
    expect(find.text(l10nEn.deleteAllLabel), findsNothing);
    expect(find.text(l10nEn.shareMealLabel), findsNothing);
    expect(find.text(l10nEn.importMealLabel), findsOneWidget);
    expect(find.text(l10nEn.saveMealAsRecipeLabel), findsNothing);
  });

  for (final type in AddMealType.values) {
    testWidgets(
      '$type opens a draft, saves to Library and leaves diary alone',
      (tester) async {
        final repo = _RecipeRepository();
        final recipes = _RecipesBloc();
        final compute = ComputeRecipeNutritionUseCase();
        final builder = RecipeBuilderBloc(
          compute,
          SaveRecipeUseCase(repo, compute),
        );
        GetIt.instance.registerSingleton<RecipeBuilderBloc>(builder);
        GetIt.instance.registerSingleton<RecipesBloc>(recipes);
        addTearDown(() async {
          GetIt.instance.unregister<RecipeBuilderBloc>();
          GetIt.instance.unregister<RecipesBloc>();
          await builder.close();
        });
        await tester.pumpWidget(
          _wrapWithMaterial(
            IntakeVerticalList(
              day: DateTime(2025, 1, 1),
              title: 'My dinner',
              listIcon: Icons.restaurant,
              addMealType: type,
              intakeList: intakes,
              usesImperialUnits: false,
              onDeleteIntakeCallback: (_, _) =>
                  fail('must not remove diary rows'),
              onCopyIntakeCallback: (_, _, _) =>
                  fail('must not add diary rows'),
            ),
          ),
        );
        await tester.tap(
          find.byType(PopupMenuButton<VerticalListPopupMenuSelections>),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10nEn.saveMealAsRecipeLabel));
        await tester.pumpAndSettle();
        expect(find.byType(RecipeBuilderScreen), findsOneWidget);
        expect(builder.state.name, 'My dinner');
        expect(builder.state.servingsCount, 1);
        expect(builder.state.ingredients.single.amount, 100);
        expect(builder.state.isExistingRecipe, isFalse);
        expect(builder.state.id, isNotEmpty);
        expect(repo.saved, isEmpty);
        await tester.enterText(
          find.byType(TextField).first,
          'Weeknight dinner',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10nEn.recipeSaveLabel));
        await tester.pumpAndSettle();
        expect(repo.saved.single.name, 'Weeknight dinner');
        expect(repo.saved.single.totalWeightG, 100);
        expect(repo.saved.single.aggregatedNutrimentsPer100.energyKcal100, 200);
        expect(repo.saved.single.id, isNot(intakes.single.meal.code));
        expect(recipes.refreshes, 1);
        expect(find.byType(RecipeBuilderScreen), findsNothing);
        expect(intakes.single.amount, 100);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('discarding a prefilled recipe writes nothing', (tester) async {
    final repo = _RecipeRepository();
    final recipes = _RecipesBloc();
    final compute = ComputeRecipeNutritionUseCase();
    final builder = RecipeBuilderBloc(
      compute,
      SaveRecipeUseCase(repo, compute),
    );
    GetIt.instance.registerSingleton<RecipeBuilderBloc>(builder);
    GetIt.instance.registerSingleton<RecipesBloc>(recipes);
    addTearDown(() async {
      GetIt.instance.unregister<RecipeBuilderBloc>();
      GetIt.instance.unregister<RecipesBloc>();
      await builder.close();
    });
    await tester.pumpWidget(
      _wrapWithMaterial(
        IntakeVerticalList(
          day: DateTime(2025, 1, 1),
          title: 'Dinner',
          listIcon: Icons.restaurant,
          addMealType: AddMealType.dinnerType,
          intakeList: intakes,
          usesImperialUnits: false,
          onDeleteIntakeCallback: (_, _) => fail('must not delete diary rows'),
        ),
      ),
    );
    await tester.tap(
      find.byType(PopupMenuButton<VerticalListPopupMenuSelections>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10nEn.saveMealAsRecipeLabel));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.discardChangesTitle), findsOneWidget);
    await tester.tap(find.text(l10nEn.discardChangesConfirmLabel));
    await tester.pumpAndSettle();
    expect(repo.saved, isEmpty);
    expect(find.byType(RecipeBuilderScreen), findsNothing);
    expect(intakes.single.amount, 100);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.3, 1.6, 2.0]) {
    testWidgets('save recipe menu fits 320px at scale $scale', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _wrapWithMaterial(
          IntakeVerticalList(
            day: DateTime(2026, 1, 1),
            title: 'Dinner',
            listIcon: Icons.restaurant,
            addMealType: AddMealType.dinnerType,
            intakeList: intakes,
            usesImperialUnits: false,
            onDeleteIntakeCallback: (_, _) {},
          ),
          scale: scale,
        ),
      );
      await tester.tap(
        find.byType(PopupMenuButton<VerticalListPopupMenuSelections>),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.saveMealAsRecipeLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
