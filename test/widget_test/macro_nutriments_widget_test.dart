import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/macro_nutriments_widget.dart';
import 'package:opennutritracker/generated/l10n.dart';

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.supportedLocales,
  locale: locale,
  home: Scaffold(body: Center(child: child)),
);

const _rings = MacroNutrientsView(
  totalCarbsIntake: 56,
  totalFatsIntake: 30,
  totalProteinsIntake: 40,
  totalCarbsGoal: 398,
  totalFatsGoal: 80,
  totalProteinsGoal: 120,
);

void main() {
  // Upstream 2b2e1572 fixed a RenderFlex failure in this widget by wrapping
  // each ring in Expanded. We do not need that fix: our outer widget is a
  // Wrap, not their Row, and a Wrap constrains children to its own maxWidth.
  // This test exists to keep it that way. The Flexible label column that made
  // upstream's layout fragile is present here too, so swapping the Wrap back
  // for a Row would break this silently, in a locale nobody checks by hand.
  //
  // Verified to discriminate: with the Wrap replaced by
  // Row(mainAxisAlignment: spaceAround), this case fails with "A RenderFlex
  // overflowed by 149 pixels on the right".
  //
  // 337.4 is the width from upstream's crash report; German carries the
  // longest macro labels.
  testWidgets('lays out at the width from upstream crash report', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const SizedBox(width: 337.4, child: _rings),
        locale: const Locale('de'),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
  });

  // Weaker than the case above, and deliberately kept anyway: this one passes
  // under the Row control too, because _MacroRing's inner Row is
  // MainAxisSize.min, which Flutter allows to hold a loose Flexible under
  // unbounded constraints. It guards against a future caller dropping the
  // rings into a horizontal scroller, not against upstream's bug.
  testWidgets('lays out when its own width is unbounded', (tester) async {
    await tester.pumpWidget(
      _app(
        const SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _rings,
        ),
        locale: const Locale('de'),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
  });
}
