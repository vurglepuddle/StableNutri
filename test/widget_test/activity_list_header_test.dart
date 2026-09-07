import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/activity_vertial_list.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// A title placed directly in a Row, beside a Spacer, is laid out against
/// unbounded width: it renders at its full intrinsic size and pushes the row
/// past its bounds instead of ellipsizing. The section header here did that
/// with the real German label at an accessibility text scale.
///
/// The fix is the shape the meal-section header in intake_vertical_list.dart
/// already uses — Expanded around the title, maxLines 1, ellipsis — so this
/// pins the two together.
Widget _app(Widget child, {required double width, required double scale}) =>
    MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      locale: const Locale('de'),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

Widget _header(String title) => ActivityVerticalList(
  day: DateTime(2026, 1, 20),
  title: title,
  userActivityList: const [],
  onItemLongPressedCallback: (_, _) {},
);

void main() {
  // 'Aktivität' is what activityLabel actually resolves to in German, and
  // 320 x 1.6 is a narrow phone at a common accessibility setting. Before the
  // fix this overflowed by 109 pixels.
  testWidgets('the header survives a narrow screen at 1.6x text', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_header('Aktivität'), width: 320, scale: 1.6));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('and holds at 280 px with 2.0x text', (tester) async {
    await tester.pumpWidget(_app(_header('Aktivität'), width: 280, scale: 2.0));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  // Not a realistic label, but it proves the title ellipsizes rather than
  // overflowing however long it gets — which is the property, not the
  // particular string.
  testWidgets('an implausibly long title ellipsizes instead', (tester) async {
    await tester.pumpWidget(
      _app(
        _header('Körperliche Aktivitäten und Trainingseinheiten heute'),
        width: 320,
        scale: 1.6,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
