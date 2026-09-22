import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/onboarding/presentation/onboarding_intro_page_body.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../../helpers/test_l10n.dart';

/// Stable collects nothing, so the welcome page states it instead of asking
/// the user to accept a policy.
void main() {
  Future<void> pumpIntroPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: OnboardingIntroPageBody()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('says there is no tracking instead of asking for consent', (
    tester,
  ) async {
    await pumpIntroPage(tester);

    expect(find.text(l10nEn.onboardingNoTrackingLabel), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('still links to the sources', (tester) async {
    await pumpIntroPage(tester);

    expect(find.text(l10nEn.onboardingIntroSourcesLinkLabel), findsOneWidget);
  });
}
