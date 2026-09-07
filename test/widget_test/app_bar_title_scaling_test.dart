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
/// The failure it guards is real and was visible on device. With no `height`
/// set on the text theme, Biryani's own metrics give a 1.78x line box, so a
/// 23 px title is a 41 px line and two lines need 82 px in a 56 px toolbar.
/// Verified to discriminate: with the ladder reverted to 1.78 the two-line
/// cases fail at 1.0x (82 vs 56), 1.15x (94 vs 64), 1.3x (106 vs 73) and 1.6x
/// (110 vs 90).
///
/// The real font is loaded on purpose. `flutter test` otherwise substitutes a
/// placeholder whose line box is exactly the font size, which is the one
/// condition under which this bug is invisible.
void main() {
  setUpAll(loadBiryani);

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
    final toolbarHeight = scaler.scale(kToolbarHeight);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppPalette.light),
        home: MediaQuery(
          data: MediaQueryData(textScaler: scaler),
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: toolbarHeight,
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
    // Pins the cause rather than the symptom: 23 px at the 1.15 ladder is a
    // ~26 px line, where Biryani's own metrics would give ~41 px.
    final (needed, _) = await measure(
      tester,
      'Edit',
      textScale: 1.0,
      maxLines: 1,
    );

    expect(needed, closeTo(23 * 1.15, 1.5));
  });
}
