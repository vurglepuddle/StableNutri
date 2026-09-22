import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/utils/calc/healthy_weight_calc.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/theme_mode_provider.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/goal_suggestion_entity.dart';
import 'package:opennutritracker/features/onboarding/domain/entity/onboarding_calorie_breakdown.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/confirm_measurements.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_fourth_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_other_options_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_overview_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_second_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_third_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/weight_range_hint.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../../../helpers/font_loading.dart';
import '../../../../helpers/test_l10n.dart';

void main() {
  setUpAll(loadAppFont);

  UserEntity user(UserWeightGoalEntity goal) => UserEntity(
    birthday: DateTime(1990, 1, 1),
    heightCM: 180,
    weightKG: 80,
    gender: UserGenderEntity.male,
    goal: goal,
    pal: UserPALEntity.lowActive,
  );

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    double scale = 1,
    bool kj = false,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => EnergyUnitProvider(usesKilojoules: kj),
          ),
          ChangeNotifierProvider(
            create: (_) => ThemeModeProvider(appTheme: AppThemeEntity.system),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppPalette.light),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: page),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget overview(OnboardingCalorieBreakdown value) =>
      OnboardingOverviewPageBody(
        setButtonActive: (_) {},
        calorieGoalDayString: value.totalKcal.toInt().toString(),
        carbsGoalString: '250',
        fatGoalString: '80',
        proteinGoalString: '100',
        breakdown: value,
      );

  test('reference range uses inclusive 18.5 and exclusive 25 BMI bounds', () {
    final range = HealthyWeightRange.forHeightCm(200);
    expect(range.minKg, 74);
    expect(range.maxKg, 100);
    expect(range.contains(74), isTrue);
    expect(range.contains(99.99), isTrue);
    expect(range.contains(100), isFalse);
    expect(range.suggestionFor(80), 80);
    expect(range.suggestionFor(110), 87);
    expect(
      () => HealthyWeightRange.forHeightCm(double.nan),
      throwsArgumentError,
    );
  });

  test('BMI can be withheld without inventing a goal', () {
    expect(
      GoalSuggestionEntity.from(
        heightCm: 170,
        weightKg: 95,
        targetWeightKg: null,
        allowBmi: false,
      ),
      isNull,
    );
    expect(
      GoalSuggestionEntity.from(
        heightCm: 170,
        weightKg: double.nan,
        targetWeightKg: 60,
      ),
      isNull,
    );
  });

  test('breakdown totals follow the production calorie calculations', () {
    for (final goal in UserWeightGoalEntity.values) {
      final person = user(goal);
      final value = OnboardingCalorieBreakdown.fromUser(person);
      expect(value.totalKcal, CalorieGoalCalc.getTotalKcalGoal(person, 0));
      expect(value.maintenanceKcal + value.adjustmentKcal, value.totalKcal);
    }
  });

  for (final kj in [false, true]) {
    testWidgets(
      'overview preserves the adjustment sign in ${kj ? 'kJ' : 'kcal'}',
      (tester) async {
        final value = OnboardingCalorieBreakdown.fromUser(
          user(UserWeightGoalEntity.loseWeight),
        );
        await pump(tester, overview(value), kj: kj);
        final adjustment = kj ? UnitCalc.kcalToKj(-500).toInt() : -500;
        expect(find.text('$adjustment ${kj ? 'kJ' : 'kcal'}'), findsOneWidget);
        expect(find.text(l10nEn.onboardingMaintenanceLabel), findsOneWidget);
      },
    );
  }

  for (final unit in BodyWeightUnit.values) {
    testWidgets(
      'applying a weight suggestion updates the ${unit.name} target',
      (tester) async {
        double? target;
        await pump(
          tester,
          OnboardingSecondPageBody(
            initialHeightCm: 180,
            initialWeightKg: 80,
            initialBodyWeightUnit: unit,
            showWeightRange: true,
            setButtonContent: (_, _, _, value, _, _, _) => target = value,
          ),
        );
        final chip = find.bySemanticsIdentifier(
          'onboarding-target-weight-suggestion',
        );
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(
          target,
          80,
          reason: 'inside the reference band preserves current weight',
        );
        if (unit == BodyWeightUnit.st) {
          final pounds = find.bySemanticsIdentifier(
            'onboarding-target-weight-pounds-input',
          );
          await tester.ensureVisible(pounds);
          await tester.enterText(pounds, '0');
          await tester.pump();
          expect(
            target,
            isNot(80),
            reason: 'the applied target remains editable',
          );
        }
      },
    );
  }

  testWidgets('no BMI suggestion is shown without adult eligibility', (
    tester,
  ) async {
    await pump(
      tester,
      OnboardingSecondPageBody(
        initialHeightCm: 170,
        initialWeightKg: 95,
        setButtonContent: (_, _, _, _, _, _, _) {},
      ),
    );
    expect(find.byType(WeightRangeHint), findsNothing);
    await pump(
      tester,
      OnboardingFourthPageBody(
        heightCm: 170,
        weightKg: 95,
        setButtonContent: (_, _) {},
      ),
    );
    expect(find.text(l10nEn.onboardingGoalSuggestedBadge), findsNothing);
  });

  for (final answer in ['change', 'dismiss', 'keep']) {
    testWidgets('unusual values require explicit Keep: $answer', (
      tester,
    ) async {
      bool? result;
      final confirmed = <(String, double)>{};
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await confirmOnboardingMeasurements(
                context,
                heightCm: 170,
                weightKg: 5,
                targetWeightKg: null,
                imperialHeight: false,
                weightUnit: BodyWeightUnit.kg,
                confirmed: confirmed,
              );
            },
            child: const Text('Next'),
          ),
        ),
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      if (answer == 'dismiss') {
        final context = tester.element(find.byType(AlertDialog));
        Navigator.of(context).pop();
      } else {
        await tester.tap(
          find.bySemanticsIdentifier('onboarding-implausible-$answer'),
        );
      }
      await tester.pumpAndSettle();
      expect(result, answer == 'keep');
      expect(confirmed.contains(('weight', 5.0)), answer == 'keep');
      if (answer == 'keep') {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      }
    });
  }

  testWidgets('multiple unusual inputs are confirmed one at a time', (
    tester,
  ) async {
    bool? result;
    final confirmed = <(String, double)>{};
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await confirmOnboardingMeasurements(
            context,
            heightCm: 50,
            weightKg: 5,
            targetWeightKg: 4,
            imperialHeight: true,
            weightUnit: BodyWeightUnit.st,
            confirmed: confirmed,
          ),
          child: const Text('Next'),
        ),
      ),
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(result, isNull);
      await tester.tap(
        find.bySemanticsIdentifier('onboarding-implausible-keep'),
      );
      await tester.pumpAndSettle();
    }
    expect(result, isTrue);
    expect(confirmed, hasLength(3));
  });

  for (final scale in [1.3, 1.6, 2.0]) {
    for (final surface in [
      'activity',
      'goal',
      'options',
      'overview',
      'range',
    ]) {
      testWidgets('$surface fits 320px at text scale $scale', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final page = switch (surface) {
          'activity' => OnboardingThirdPageBody(setButtonContent: (_, _) {}),
          'goal' => OnboardingFourthPageBody(
            heightCm: 170,
            weightKg: 95,
            allowBmiSuggestion: true,
            setButtonContent: (_, _) {},
          ),
          'options' => OnboardingOtherOptionsPageBody(
            setPageContent: (_, _, _, _, _) {},
            initialTheme: AppThemeEntity.system,
            initialFoodSourceToggles: const {},
            initialDailyReminderEnabled: false,
            initialUseMaterialYou: true,
            initialAccentColor: null,
          ),
          'overview' => overview(
            OnboardingCalorieBreakdown.fromUser(
              user(UserWeightGoalEntity.gainWeight),
            ),
          ),
          _ => WeightRangeHint(
            heightCm: 170,
            weightKg: 95,
            unit: BodyWeightUnit.st,
            onApply: (_) {},
          ),
        };
        await pump(tester, page, scale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
