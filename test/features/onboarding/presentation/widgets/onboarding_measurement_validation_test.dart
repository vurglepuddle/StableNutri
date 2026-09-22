import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_second_page_body.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../../../helpers/font_loading.dart';
import '../../../../helpers/test_l10n.dart';

void main() {
  setUpAll(loadAppFont);

  Future<void> pumpPage(
    WidgetTester tester, {
    BodyWeightUnit unit = BodyWeightUnit.kg,
    bool imperialHeight = false,
    bool restoreValues = false,
    double scale = 1,
    required ValueNotifier<int> errors,
    required ValueChanged<bool> onValid,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppPalette.light),
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: OnboardingSecondPageBody(
            initialBodyWeightUnit: unit,
            initialHeightImperial: imperialHeight,
            initialHeightCm: restoreValues ? 170 : null,
            initialWeightKg: restoreValues ? 70 : null,
            showErrorsSignal: errors,
            setButtonContent: (active, _, _, _, _, _, _) => onValid(active),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String id, String value) async {
    final field = find.bySemanticsIdentifier(id);
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pump();
  }

  testWidgets('typing stays quiet until blur while readiness follows input', (
    tester,
  ) async {
    final errors = ValueNotifier(0);
    addTearDown(errors.dispose);
    var ready = false;
    await pumpPage(tester, errors: errors, onValid: (value) => ready = value);
    await enter(tester, 'onboarding-height-field', '1');
    expect(ready, isFalse);
    expect(find.text(l10nEn.onboardingWrongHeightLabel), findsNothing);
    await enter(tester, 'onboarding-weight-field', '70');
    expect(find.text(l10nEn.onboardingWrongHeightLabel), findsOneWidget);
    await enter(tester, 'onboarding-height-field', '170');
    expect(ready, isTrue);
    expect(find.text(l10nEn.onboardingWrongHeightLabel), findsNothing);
  });

  testWidgets('blocked Next reveals errors on untouched metric fields', (
    tester,
  ) async {
    final errors = ValueNotifier(0);
    addTearDown(errors.dispose);
    await pumpPage(tester, errors: errors, onValid: (_) {});
    errors.value++;
    await tester.pump();
    expect(find.text(l10nEn.onboardingWrongHeightLabel), findsOneWidget);
    // The optional empty target must not be marked invalid.
    expect(find.text(l10nEn.onboardingWrongWeightLabel), findsOneWidget);
  });

  testWidgets('blocked Next reveals errors for feet/inches and stones', (
    tester,
  ) async {
    final errors = ValueNotifier(0);
    addTearDown(errors.dispose);
    await pumpPage(
      tester,
      errors: errors,
      onValid: (_) {},
      unit: BodyWeightUnit.st,
      imperialHeight: true,
    );
    errors.value++;
    await tester.pump();
    expect(find.text(l10nEn.onboardingWrongHeightLabel), findsOneWidget);
    expect(find.text(l10nEn.onboardingWrongWeightLabel), findsOneWidget);
  });

  testWidgets(
    'partial stones target blocks Next; clearing both parts permits it',
    (tester) async {
      final errors = ValueNotifier(0);
      addTearDown(errors.dispose);
      var ready = false;
      await pumpPage(
        tester,
        errors: errors,
        onValid: (value) => ready = value,
        unit: BodyWeightUnit.st,
        restoreValues: true,
      );
      await enter(tester, 'onboarding-target-weight-stones-input', '10');
      expect(ready, isFalse);
      errors.value++;
      await tester.pump();
      expect(find.text(l10nEn.onboardingWrongWeightLabel), findsOneWidget);
      await enter(tester, 'onboarding-target-weight-pounds-input', '2');
      expect(ready, isTrue);
      expect(find.text(l10nEn.onboardingWrongWeightLabel), findsNothing);
      await enter(tester, 'onboarding-target-weight-stones-input', '');
      expect(ready, isFalse);
      await enter(tester, 'onboarding-target-weight-pounds-input', '');
      expect(ready, isTrue);
      expect(find.text(l10nEn.onboardingWrongWeightLabel), findsNothing);
    },
  );

  testWidgets('invalid metric target blocks Next until corrected or cleared', (
    tester,
  ) async {
    final errors = ValueNotifier(0);
    addTearDown(errors.dispose);
    var ready = false;
    await pumpPage(
      tester,
      errors: errors,
      onValid: (value) => ready = value,
      restoreValues: true,
    );
    await enter(tester, 'onboarding-target-weight-field', '0');
    expect(ready, isFalse);
    errors.value++;
    await tester.pump();
    expect(find.text(l10nEn.onboardingWrongWeightLabel), findsOneWidget);
    await enter(tester, 'onboarding-target-weight-field', '');
    expect(ready, isTrue);
    expect(find.text(l10nEn.onboardingWrongWeightLabel), findsNothing);
  });

  testWidgets('replacing the error signal removes the old listener', (
    tester,
  ) async {
    final first = ValueNotifier(0);
    final second = ValueNotifier(0);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await pumpPage(tester, errors: first, onValid: (_) {});
    await pumpPage(tester, errors: second, onValid: (_) {});
    first.value++;
    await tester.pump();
    expect(find.text(l10nEn.onboardingWrongHeightLabel), findsNothing);
    second.value++;
    await tester.pump();
    expect(find.text(l10nEn.onboardingWrongHeightLabel), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    second.value++;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.3, 1.6, 2.0]) {
    testWidgets('split-field errors fit a 320px viewport at $scale text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final errors = ValueNotifier(0);
      addTearDown(errors.dispose);
      await pumpPage(
        tester,
        errors: errors,
        onValid: (_) {},
        unit: BodyWeightUnit.st,
        imperialHeight: true,
        scale: scale,
      );
      errors.value++;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
