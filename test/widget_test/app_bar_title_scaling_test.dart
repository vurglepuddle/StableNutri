import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';

import '../helpers/font_loading.dart';

/// Screen titles have to survive a raised system font scale.
///
/// This app is used at an elevated text scale for accessibility, so "fits at
/// 1.0" is not the bar — anything that only fits unscaled is broken in normal
/// use. An AppBar clips silently rather than throwing, which is why this went
/// unnoticed: nothing in the suite fails, the top and bottom of the title just
/// disappear.
///
/// The failure it guards is real and was seen on device. With no `height` set
/// on the text theme, the line box comes from the font's own metrics — the
/// previous face, Biryani, gave 1.78x, so a 23 px title became a 41 px line
/// and two lines needed 82 px in a 56 px toolbar. Commissioner is 1.223x, but
/// the guard is about the type scale staying explicit, not about which font is
/// installed: reverting the ladder to a font's raw metrics is exactly the
/// change this has to catch.
///
/// The real font is loaded on purpose. `flutter test` otherwise substitutes a
/// placeholder whose line box is exactly the font size, which is the one
/// condition under which this bug is invisible.
void main() {
  setUpAll(loadAppFont);

  /// The height one title needs, against the height its toolbar gives it.
  Future<(double needed, double available)> measure(
    WidgetTester tester,
    String title, {
    required double textScale,
    int maxLines = 2,
  }) async {
    // A phone, not the 800x600 default test surface: at 800 px wide the title
    // never wraps and the two-line case would prove nothing.
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final scaler = TextScaler.linear(textScale);

    // Whatever the screens themselves ask for, via the same helper.
    late double toolbarHeight;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppPalette.light),
        home: MediaQuery(
          data: MediaQueryData(textScaler: scaler),
          child: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                toolbarHeight: toolbarHeight = appBarHeightForTitle(
                  context,
                  titleLines: maxLines,
                ),
                title: Text(
                  title,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Recipe'),
                  ),
                ],
              ),
              body: const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Measure what the title *needs*, not the box it was given. An AppBar
    // clips its title rather than letting it overflow, so the laid-out size
    // is already clamped to the toolbar and reading it back would report a
    // fit no matter how tall the text really is — the same blindness that let
    // this ship. Re-lay the resolved span at the width the title actually got.
    final finder = find.text(title);
    final width = tester.getSize(finder).width;
    final rich = tester.widget<RichText>(
      find.descendant(of: finder, matching: find.byType(RichText)),
    );
    final painter = TextPainter(
      text: rich.text,
      textDirection: TextDirection.ltr,
      textScaler: rich.textScaler,
      maxLines: maxLines,
    )..layout(maxWidth: width);

    return (painter.height, toolbarHeight);
  }

  // 1.0 is the baseline; the rest are scales a person actually sets. Android
  // offers up to 2.0 in accessibility settings.
  for (final scale in [1.0, 1.15, 1.3, 1.6, 2.0]) {
    testWidgets('a two-line title fits its toolbar at ${scale}x', (
      tester,
    ) async {
      // Long enough to wrap at every scale once the actions take their width.
      final (needed, available) = await measure(
        tester,
        'Rezept bearbeiten',
        textScale: scale,
      );

      expect(
        needed,
        lessThanOrEqualTo(available),
        reason:
            'the title needs ${needed.toStringAsFixed(1)} px but the toolbar '
            'gives ${available.toStringAsFixed(1)} px, so it is clipped top '
            'and bottom',
      );
    });

    // Passes under the 1.78 control too, and kept deliberately: it documents
    // *why* single-line titles never showed the bug. Material's AppBar clamps
    // title text scaling at 1.34, which holds even a 1.78x line to 54.9 px,
    // just inside the unscaled 56. The clamp is the framework's, not ours, so
    // this pins the assumption rather than the fix.
    testWidgets('a one-line title fits the unscaled toolbar at ${scale}x', (
      tester,
    ) async {
      final (needed, _) = await measure(
        tester,
        'Edit',
        textScale: scale,
        maxLines: 1,
      );

      expect(
        needed,
        lessThanOrEqualTo(kToolbarHeight),
        reason:
            'a single line needs ${needed.toStringAsFixed(1)} px, which does '
            'not fit the unscaled 56 px toolbar used by screens that do not '
            'override toolbarHeight',
      );
    });
  }

  testWidgets('the heading line box is the ladder value, not the font metric', (
    tester,
  ) async {
    // Pins the cause rather than the symptom. 23 px at the 1.25 ladder is a
    // ~29 px line; left to Commissioner's own metrics it would be ~28.7, and
    // to Biryani's it was ~41. The tolerance is tight enough that swapping the
    // explicit height for a raw font metric shows up here.
    final (needed, _) = await measure(
      tester,
      'Edit',
      textScale: 1.0,
      maxLines: 1,
    );

    expect(needed, closeTo(23 * 1.25, 1.0));
  });

  // Commissioner's declared descent (0.206 em) barely clears its own
  // descender ink (0.204 em), so a box tighter than about 1.22 cuts the tails
  // off g, j, p, q and y. The ladder sits above that on purpose; this pins it.
  testWidgets('descenders are not clipped by the ladder', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppPalette.light),
        home: const Scaffold(body: Center(child: Text('gjpqy'))),
      ),
    );
    await tester.pumpAndSettle();

    final rich = tester.widget<RichText>(
      find.descendant(of: find.text('gjpqy'), matching: find.byType(RichText)),
    );
    final painter = TextPainter(
      text: rich.text,
      textDirection: TextDirection.ltr,
      textScaler: rich.textScaler,
    )..layout();
    final metrics = painter.computeLineMetrics().single;
    final fontSize = (rich.text.style?.fontSize)!;

    // 0.204 em is where Commissioner's descender ink actually reaches.
    expect(
      metrics.descent,
      greaterThanOrEqualTo(0.204 * fontSize),
      reason:
          'the line box gives ${metrics.descent.toStringAsFixed(2)} px of '
          'descent for a ${fontSize.toStringAsFixed(0)} px font, but the ink '
          'needs ${(0.204 * fontSize).toStringAsFixed(2)} px',
    );
  });
}
