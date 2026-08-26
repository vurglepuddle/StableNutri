import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mockito/mockito.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_nutriments_dbo.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/merge_custom_meals_usecase.dart';
import 'package:opennutritracker/features/recipes/presentation/library_filter.dart';
import 'package:opennutritracker/features/recipes/presentation/widgets/custom_meals_tab.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/custom_meals_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../helpers/fake_hive_db_provider.dart';
import '../helpers/hive_test_setup.dart';

class _MockGetIntakeUsecase extends Mock implements GetIntakeUsecase {}

class _MockDeleteIntakeUsecase extends Mock implements DeleteIntakeUsecase {}

class _MockAddTrackedDayUsecase extends Mock implements AddTrackedDayUsecase {}

class _MockMergeCustomMealsUseCase extends Mock
    implements MergeCustomMealsUseCase {}

MealDBO _savedMeal() => MealDBO(
  code: 'saved-1',
  name: 'Comfort soup',
  brands: 'Home',
  thumbnailImageUrl: null,
  mainImageUrl: null,
  url: null,
  mealQuantity: '100',
  mealUnit: 'g',
  servingQuantity: null,
  servingUnit: 'g',
  servingSize: null,
  nutriments: MealNutrimentsDBO(
    energyKcal100: 90,
    carbohydrates100: null,
    fat100: null,
    proteins100: null,
    sugars100: null,
    saturatedFat100: null,
    fiber100: null,
  ),
  source: MealSourceDBO.custom,
  isFavorite: true,
  isRescue: true,
);

Widget _app(
  CustomMealsBloc bloc, {
  LibraryFilter filter = LibraryFilter.all,
  double textScale = 1,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.delegate.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: BlocProvider.value(
        value: bloc,
        child: CustomMealsTab(usesImperialUnits: false, filter: filter),
      ),
    ),
  );
}

void main() {
  late Box<MealDBO> box;
  late CustomMealsBloc bloc;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Hive.init('.');
    registerHiveAdaptersOnce();
  });

  setUp(() async {
    box = await Hive.openBox<MealDBO>(
      'library_widget_${DateTime.now().microsecondsSinceEpoch}',
    );
    final dataSource = CustomMealDataSource(
      FakeHiveDBProvider(customMealBox: box),
    );
    await dataSource.saveCustomMeal(_savedMeal());
    bloc = CustomMealsBloc(
      dataSource,
      _MockGetIntakeUsecase(),
      _MockDeleteIntakeUsecase(),
      _MockAddTrackedDayUsecase(),
      _MockMergeCustomMealsUseCase(),
    )..add(LoadCustomMealsEvent());
    await bloc.stream.firstWhere((state) => state is CustomMealsLoadedState);
  });

  tearDown(() async {
    await bloc.close();
    await box.deleteFromDisk();
  });

  testWidgets('saved-meal actions fit a 320 px wide screen', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(bloc, textScale: 1.6));
    await tester.pumpAndSettle();

    expect(find.text('Comfort soup'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Remove rescue label'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rescue filter includes a labelled meal', (tester) async {
    await tester.pumpWidget(_app(bloc, filter: LibraryFilter.rescue));
    await tester.pumpAndSettle();

    expect(find.text('Comfort soup'), findsOneWidget);
    expect(find.textContaining('No Library items'), findsNothing);
  });
}
