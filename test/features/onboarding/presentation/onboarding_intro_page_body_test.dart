import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/onboarding/presentation/onboarding_intro_page_body.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUpAll(() {
    // The widget shows AppConst.getVersionNumber() in a FutureBuilder, which
    // calls PackageInfo.fromPlatform(). Mock it so the widget renders in tests.
    PackageInfo.setMockInitialValues(
      appName: 'OpenNutriTracker',
      packageName: 'com.example.opennutritracker',
      version: '1.2.0',
      buildNumber: '46',
      buildSignature: '',
    );
  });

  Future<void> pumpIntroPage(
    WidgetTester tester, {
    required void Function(bool acceptedPolicy, bool acceptedData)
    onSetPageContent,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [S.delegate],
        supportedLocales: S.delegate.supportedLocales,
        home: Scaffold(
          body: OnboardingIntroPageBody(setPageContent: onSetPageContent),
        ),
      ),
    );
    // Let the version-number FutureBuilder resolve before continuing.
    await tester.pumpAndSettle();
  }

  testWidgets('offers only the policy checkbox, unchecked', (tester) async {
    await pumpIntroPage(tester, onSetPageContent: (_, _) {});

    final checkboxes = tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .toList();
    // Stable collects nothing, so there is no data-collection consent to ask
    // for. The policy checkbox is a legal acceptance and stays.
    expect(checkboxes, hasLength(1));
    expect(
      checkboxes.single.value,
      isFalse,
      reason: 'policy checkbox starts unchecked',
    );
    expect(find.bySemanticsLabel('onboarding-checkbox-data'), findsNothing);
  });

  testWidgets(
    'tapping the policy checkbox reports (true, false) and checks the box',
    (tester) async {
      bool? lastPolicy;
      bool? lastData;
      await pumpIntroPage(
        tester,
        onSetPageContent: (policy, data) {
          lastPolicy = policy;
          lastData = data;
        },
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(lastPolicy, isTrue);
      expect(lastData, isFalse);
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).first).value,
        isTrue,
      );
    },
  );

  testWidgets('the data-collection flag is never reported as accepted', (
    tester,
  ) async {
    final reportedData = <bool>[];
    await pumpIntroPage(
      tester,
      onSetPageContent: (policy, data) => reportedData.add(data),
    );

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();

    // Nothing in the UI can turn it on any more.
    expect(reportedData, isNotEmpty);
    expect(reportedData, everyElement(isFalse));
  });

  testWidgets('tapping the policy checkbox twice toggles it back off', (
    tester,
  ) async {
    final reportedStates = <(bool, bool)>[];
    await pumpIntroPage(
      tester,
      onSetPageContent: (policy, data) {
        reportedStates.add((policy, data));
      },
    );

    final policyBox = find.byType(Checkbox).first;
    await tester.tap(policyBox);
    await tester.pump();
    await tester.tap(policyBox);
    await tester.pump();

    expect(reportedStates, equals([(true, false), (false, false)]));
    expect(tester.widget<Checkbox>(policyBox).value, isFalse);
  });

  testWidgets(
    'tapping the policy ListTile (not just the checkbox) also toggles',
    (tester) async {
      bool? lastPolicy;
      await pumpIntroPage(
        tester,
        onSetPageContent: (policy, _) {
          lastPolicy = policy;
        },
      );

      // The policy ListTile has onTap wired to _togglePolicy, so tapping the
      // surrounding row (e.g., the policy text) should also flip the checkbox.
      final policyTile = find.ancestor(
        of: find.byType(Checkbox).first,
        matching: find.byType(ListTile),
      );
      await tester.tap(policyTile);
      await tester.pump();

      expect(lastPolicy, isTrue);
    },
  );
}
