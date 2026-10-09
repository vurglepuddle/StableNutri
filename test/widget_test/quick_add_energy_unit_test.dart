import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/presentation/widgets/quick_add_bottom_sheet.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../helpers/test_l10n.dart';

class _Intakes extends Fake implements AddIntakeUsecase {
  final saved = <IntakeEntity>[];

  @override
  Future<void> addIntake(IntakeEntity intake) async => saved.add(intake);
}

class _Days extends Fake implements AddTrackedDayUsecase {
  double? calories;

  @override
  Future<bool> hasTrackedDay(DateTime day) async => true;

  @override
  Future<void> addDayCaloriesTracked(DateTime day, double value) async {
    calories = value;
  }

  @override
  Future<void> addDayMacrosTracked(
    DateTime day, {
    double? carbsTracked,
    double? fatTracked,
    double? proteinTracked,
  }) async {}
}

class _Home extends Fake implements HomeBloc {
  @override
  void add(HomeEvent event) {}
}

class _Diary extends Fake implements DiaryBloc {
  @override
  void add(DiaryEvent event) {}
}

class _Calendar extends Fake implements CalendarDayBloc {
  @override
  void add(CalendarDayEvent event) {}
}

void main() {
  late _Intakes intakes;
  late _Days days;
  late EnergyUnitProvider preference;

  Finder field(String identifier) => find.descendant(
    of: find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.identifier == identifier,
    ),
    matching: find.byType(TextField),
  );

  Future<void> pumpSheet(
    WidgetTester tester, {
    bool prefersKj = false,
    double textScale = 1,
    double width = 411,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    intakes = _Intakes();
    days = _Days();
    preference = EnergyUnitProvider(usesKilojoules: prefersKj);
    locator.registerSingleton<AddIntakeUsecase>(intakes);
    locator.registerSingleton<AddTrackedDayUsecase>(days);
    locator.registerSingleton<HomeBloc>(_Home());
    locator.registerSingleton<DiaryBloc>(_Diary());
    locator.registerSingleton<CalendarDayBloc>(_Calendar());
    addTearDown(() async {
      await locator.reset();
      preference.dispose();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: preference,
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          routes: {
            NavigationOptions.mainRoute: (context) => Scaffold(
              body: Text(
                EnergyDisplay.formatWithUnit(
                  context,
                  intakes.saved.single.totalKcal,
                ),
              ),
            ),
          },
          home: Scaffold(
            body: QuickAddBottomSheet(
              intakeType: IntakeTypeEntity.snack,
              day: DateTime(2026, 10, 9),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseUnit(WidgetTester tester, bool kj) async {
    final selector = find.byKey(const ValueKey('quick-add-energy-unit'));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text(kj ? l10nEn.kjLabel : l10nEn.kcalLabel).last);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.pumpAndSettle();
    final button = find.widgetWithText(
      FilledButton,
      l10nEn.quickAddSubmitLabel,
    );
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final prefersKj in [false, true]) {
    for (final entersKj in [false, true]) {
      testWidgets(
        'Quick Add input kJ=$entersKj saves for preference kJ=$prefersKj',
        (tester) async {
          await pumpSheet(tester, prefersKj: prefersKj);
          final selector = tester.widget<DropdownButton<bool>>(
            find.byKey(const ValueKey('quick-add-energy-unit')),
          );
          expect(selector.value, prefersKj);
          await tester.enterText(field('quick-add-title'), 'Snack');
          await chooseUnit(tester, entersKj);
          await tester.enterText(
            field('quick-add-energy'),
            entersKj ? '1046' : '250',
          );
          await save(tester);
          expect(intakes.saved.single.totalKcal, closeTo(250, 1e-10));
          expect(days.calories, closeTo(250, 1e-10));
          expect(intakes.saved.single.meal.nutriments.carbohydrates100, isNull);
          expect(preference.usesKilojoules, prefersKj);
          expect(
            find.text(
              prefersKj ? '1046 ${l10nEn.kjLabel}' : '250 ${l10nEn.kcalLabel}',
            ),
            findsOneWidget,
          );
        },
      );
    }
  }

  testWidgets('unit switches preserve exact energy and leave macros alone', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tester.enterText(field('quick-add-title'), 'Snack');
    await chooseUnit(tester, true);
    await tester.enterText(field('quick-add-energy'), '1000,01');
    await tester.enterText(field('quick-add-carbs'), '30');
    await tester.enterText(field('quick-add-fat'), '10');
    await tester.enterText(field('quick-add-protein'), '10');
    await chooseUnit(tester, false);
    expect(
      tester.widget<TextField>(field('quick-add-energy')).controller!.text,
      '239.01',
    );
    await chooseUnit(tester, true);
    await chooseUnit(tester, false);
    await save(tester);
    final intake = intakes.saved.single;
    expect(intake.totalKcal, closeTo(UnitCalc.kjToKcal(1000.01), 1e-10));
    expect(days.calories, closeTo(intake.totalKcal, 1e-10));
    expect(intake.totalCarbsGram, 30);
    expect(intake.totalFatsGram, 10);
    expect(intake.totalProteinsGram, 10);
  });

  testWidgets('editing a converted amount saves the newly typed value', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tester.enterText(field('quick-add-title'), 'Snack');
    await tester.enterText(field('quick-add-energy'), '250');
    await chooseUnit(tester, true);
    await tester.enterText(field('quick-add-energy'), '2000');
    await save(tester);
    expect(
      intakes.saved.single.totalKcal,
      closeTo(UnitCalc.kjToKcal(2000), 1e-10),
    );
  });

  testWidgets('switching units keeps an empty field empty and save disabled', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tester.enterText(field('quick-add-title'), 'Snack');
    await chooseUnit(tester, true);
    expect(
      tester.widget<TextField>(field('quick-add-energy')).controller!.text,
      isEmpty,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.enterText(field('quick-add-energy'), '0');
    await chooseUnit(tester, false);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  for (final scale in [1.3, 1.6, 2.0]) {
    testWidgets('Quick Add unit choice fits at 320px and ${scale}x text', (
      tester,
    ) async {
      await pumpSheet(tester, width: 320, textScale: scale);
      await chooseUnit(tester, true);
      expect(tester.takeException(), isNull);
    });
  }
}
