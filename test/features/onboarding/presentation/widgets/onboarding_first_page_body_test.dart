import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_first_page_body.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/core/utils/bounds/validator.dart';

import '../../../../helpers/test_l10n.dart';

/// The adult-equation notice on the birthday page. The calorie goal comes
/// from the IOM 2005 adult equations, so a 13-17 year old is told where the
/// number comes from rather than handed it silently.
void main() {
  final noticeText = l10nEn.onboardingAdultEquationNotice;

  Future<void> pumpFirstPage(WidgetTester tester, {DateTime? birthday}) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(
          body: OnboardingFirstPageBody(
            setPageContent: (_, _, _, _) {},
            initialBirthday: birthday,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  DateTime yearsAgo(int years) {
    final now = DateTime.now();
    return DateTime(now.year - years, now.month, now.day);
  }

  testWidgets('no birthday chosen yet shows no notice', (tester) async {
    await pumpFirstPage(tester);

    expect(find.text(noticeText), findsNothing);
  });

  testWidgets('a 15 year old sees the notice', (tester) async {
    await pumpFirstPage(tester, birthday: yearsAgo(15));

    expect(find.text(noticeText), findsOneWidget);
  });

  testWidgets('a 13 year old sees the notice', (tester) async {
    await pumpFirstPage(tester, birthday: yearsAgo(13));

    expect(find.text(noticeText), findsOneWidget);
  });

  testWidgets('an adult does not', (tester) async {
    await pumpFirstPage(tester, birthday: yearsAgo(30));

    expect(find.text(noticeText), findsNothing);
  });

  testWidgets('exactly 18 does not', (tester) async {
    await pumpFirstPage(tester, birthday: yearsAgo(18));

    expect(find.text(noticeText), findsNothing);
  });

  testWidgets('new birthday picker opens year-first at age 30', (tester) async {
    await pumpFirstPage(tester);
    await tester.tap(find.bySemanticsIdentifier('onboarding-birthday-field'));
    await tester.pumpAndSettle();
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(find.byType(YearPicker), findsOneWidget);
    expect(picker.initialDate, ValueValidator.getInitialBirthdayDate());
    expect(picker.firstDate, ValueValidator.getFirstDate());
    expect(picker.lastDate, ValueValidator.getLastDate());
  });

  testWidgets('old out-of-range birthday is clamped only for the picker', (
    tester,
  ) async {
    final stored = DateTime(2099, 1, 1);
    await pumpFirstPage(tester, birthday: stored);
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    final previousText = field.controller!.text;
    await tester.tap(find.bySemanticsIdentifier('onboarding-birthday-field'));
    await tester.pumpAndSettle();
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.initialDate, ValueValidator.getLastDate());
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(field.controller!.text, previousText);
    expect(tester.takeException(), isNull);
  });
}
