import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The horizontal Stable lockup: the cream badge with its stacked mark, plus
/// the wordmark in Ovo.
///
/// Two authored variants rather than a runtime tint — `flutter_svg` can only
/// colour a whole picture, and only the wordmark actually changes between
/// themes. The badge carries its own background, so the mark inside it stays
/// as designed on either canvas.
///
/// **The asset names describe the artwork, not the canvas**, so the selection
/// below reads inverted and is meant to: the *dark* logo is the one that shows
/// up on a *light* background.
///
/// Both assets are flattened. The design tool exports `class="cls-1"` plus a
/// `<style>` block, and `flutter_svg` does not implement CSS, so an unflattened
/// export renders as nothing at all — see CLAUDE.md before adding a new SVG.
class StableWordmark extends StatelessWidget {
  const StableWordmark({super.key, this.height = 32});

  /// Dark green (`#173525`) wordmark — for the light canvas.
  static const _darkLogo = 'assets/icon/logo_stable_dark.svg';

  /// Off-white (`#e5e2dd`) wordmark — for the dark canvas.
  static const _lightLogo = 'assets/icon/logo_stable_light.svg';

  /// Intrinsic aspect ratio of the artwork (202.478 x 58.483).
  static const _aspectRatio = 202.478 / 58.483;

  final double height;

  @override
  Widget build(BuildContext context) {
    // Follow the active Material theme rather than the platform brightness, so
    // a user who has forced a theme against their device setting sees the
    // variant that matches what is actually on screen.
    final isDarkCanvas = Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(
      isDarkCanvas ? _lightLogo : _darkLogo,
      height: height,
      width: height * _aspectRatio,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      semanticsLabel: S.of(context).appTitle,
    );
  }
}
