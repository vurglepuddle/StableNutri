import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:opennutritracker/features/onboarding/onboarding_screen.dart';
import 'package:opennutritracker/main.dart' as app;

/// Single-boot smoke for the whole first-run path. Everything here shares
/// one `app.main()` deliberately: `initLocator()` registers its GetIt
/// singletons without a re-registration guard, so a second `app.main()` in
/// the same process would throw. Keeping the checks in one boot (rather than
/// several test files) is what lets the suite run unsharded — a single
/// `flutter test integration_test/` per platform that pays the build and
/// simulator cost once.
///
/// The assertions cover three failure surfaces that cascade from that boot:
///   - boot health: `main()` finishes and lands a MaterialApp, and nothing
///     trips `FlutterError.onError` along the way. The first catches loud
///     failures (Hive can't open, secure storage can't derive its AES key,
///     Supabase init throws, a missing GetIt dependency); the second catches
///     quiet ones (a Hive type-id collision, a dropped `await` in plugin
///     init, a half-broken notification re-register) that leave something
///     half-initialised without crashing the visible screen.
///   - routing: a fresh install has no user data, so `hasUserData()` returns
///     false and the router lands on OnboardingScreen with IntroductionScreen
///     mounted (which only happens once OnboardingBloc reaches its loaded
///     state).
///   - localisation: the intl delegates load and the English `appDescription`
///     ARB entry reaches the intro page body and renders. A future copy
///     change forces this test to be updated alongside it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'fresh install boots cleanly into a fully-rendered onboarding intro',
    (WidgetTester tester) async {
      final caught = <FlutterErrorDetails>[];
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        caught.add(details);
        original?.call(details);
      };
      addTearDown(() => FlutterError.onError = original);

      await app.main();
      await tester.pumpAndSettle(const Duration(seconds: 30));

      // Boot health.
      expect(find.byType(MaterialApp), findsOneWidget,
          reason: 'app should reach a MaterialApp');
      expect(
        caught,
        isEmpty,
        reason: 'no Flutter errors should fire during boot, got: '
            '${caught.map((e) => e.exception).toList()}',
      );

      // Routing: with no user data, the first screen is onboarding.
      expect(find.byType(OnboardingScreen), findsOneWidget,
          reason: 'with no user data, the first screen should be onboarding');

      // Bloc state: IntroductionScreen mounts only after the bloc reaches
      // OnboardingLoadedState.
      expect(find.byType(IntroductionScreen), findsOneWidget,
          reason: 'OnboardingBloc should transition into loaded state');

      // Localisation: a verbatim copy of the English ARB entry for
      // appDescription, rendered by the intro page body.
      const appDescription =
          'Stable is a free and open-source calorie and '
          'nutrient tracker that respects your privacy.';
      expect(find.text(appDescription), findsOneWidget,
          reason: 'the localised appDescription should render on the intro page');
    },
  );
}
