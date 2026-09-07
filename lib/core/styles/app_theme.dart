import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

/// Friendly, highly readable type. Commissioner carries everything — a low
/// contrast humanist sans, warm and open without being cute, and calm enough
/// to stay legible in dense lists. Heavy weights give the hero numbers
/// presence without a separate display face; Ovo appears only in the logo,
/// where it is already outlined into paths.
///
/// Commissioner replaced Biryani because Biryani has **no Cyrillic and no
/// Greek** — 0 of 256 code points. Ukrainian is a shipped locale and Russian
/// was wanted, so both fell back to whatever the OS supplied, and any Cyrillic
/// food name a user typed rendered in a different face mid-list. Commissioner
/// covers every locale this app ships except Chinese, which no Latin text face
/// includes; CJK stays on the system fallback deliberately rather than
/// bundling ~15 MB of Noto.
///
/// It also has the full 100–900 ladder, including the Medium (500) Biryani
/// lacked. Body text still sits at w400 and the app-wide weights are unchanged
/// by the swap; 500 is simply available now if the scale is ever revisited.
/// There are no italics.
///
/// ## Line heights are set explicitly, and must stay that way
///
/// Every style below sets `height`. Left unset, the line box comes from the
/// font's own metrics, and that is how the previous face shipped clipped
/// screen titles: Biryani is a Devanagari family whose metrics reserve room
/// for marks above and below the baseline, giving a **1.765 em** natural line.
/// A 23 px title became a 41 px line, so a two-line AppBar title needed 82 px
/// in a 56 px toolbar and lost the top and bottom of both rows.
///
/// Commissioner is far better behaved — **1.223 em** natural, against 1.364
/// for Nunito and 1.500 for Poppins — but the rule stands regardless of face.
/// An explicit ladder is what keeps layout independent of whichever font is
/// installed next.
///
/// The floor is not arbitrary. With even leading distribution the box has to
/// stay at or above **1.22**, because Commissioner's declared descent (0.206
/// em) barely clears its own descender ink (0.204 em): tighten past that and
/// the tails of g, j, p, q and y are cut. Nothing below 1.22 belongs here.
///
/// This app is used at a raised system font scale for accessibility, so
/// anything that only fits at 1.0 is broken in normal use. See "Type scale and
/// text scaling" in Design/session-handoff.md.
const _displayHeight = 1.25;
const _headlineHeight = 1.25;
const _titleHeight = 1.30;
const _bodyHeight = 1.45;
const _labelHeight = 1.35;

TextTheme appTextTheme(AppPalette p) {
  const f = 'Commissioner';
  TextStyle s(
    double size,
    FontWeight w, {
    required double height,
    double spacing = 0,
    Color? color,
  }) => TextStyle(
    fontFamily: f,
    fontSize: size,
    fontWeight: w,
    height: height,
    // Split the leading evenly above and below, rather than in proportion to
    // the font's own ascent and descent, which is the default. Proportional
    // distribution shrinks the declared ascent as soon as `height` tightens
    // the box, which drags the baseline up and cuts the tops of letters — it
    // is what left a sliver clipped off Biryani's titles even after the
    // heights were set. Even distribution keeps the glyphs centred in whatever
    // box the ladder asks for, and is the better model for any font.
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: spacing,
    color: color ?? p.textStrong,
  );
  return TextTheme(
    displayLarge: s(57, FontWeight.w700, spacing: -1, height: _displayHeight),
    displayMedium: s(
      45,
      FontWeight.w700,
      spacing: -0.5,
      height: _displayHeight,
    ),
    displaySmall: s(36, FontWeight.w700, height: _displayHeight),
    headlineLarge: s(32, FontWeight.w700, height: _headlineHeight),
    headlineMedium: s(28, FontWeight.w600, height: _headlineHeight),
    headlineSmall: s(23, FontWeight.w600, height: _headlineHeight),
    titleLarge: s(21, FontWeight.w600, height: _titleHeight),
    titleMedium: s(16, FontWeight.w600, height: _titleHeight),
    titleSmall: s(14, FontWeight.w600, height: _titleHeight),
    bodyLarge: s(16, FontWeight.w400, height: _bodyHeight),
    bodyMedium: s(14, FontWeight.w400, height: _bodyHeight),
    bodySmall: s(
      12.5,
      FontWeight.w400,
      color: p.textMuted,
      height: _bodyHeight,
    ),
    labelLarge: s(15, FontWeight.w600, height: _labelHeight),
    labelMedium: s(13, FontWeight.w600, height: _labelHeight),
    labelSmall: s(
      11.5,
      FontWeight.w600,
      color: p.textMuted,
      height: _labelHeight,
    ),
  );
}

/// The toolbar height an AppBar needs for a title of [titleLines] lines.
///
/// `kToolbarHeight` is 56 and does not grow, so a wrapped title is clipped
/// rather than overflowed — silently, with no stripes and no exception. Every
/// screen whose title can wrap should size its bar from the type scale instead
/// of assuming the constant fits.
///
/// Two details this has to account for, both easy to get wrong:
///
///  * Material clamps AppBar *title* scaling at 1.34 while the caller scales
///    the toolbar by the full factor, so above 1.34 the bar grows and the
///    title does not. The binding case is therefore at or below 1.34, not at
///    the largest scale.
///  * The title's line box is `fontSize * height` from the theme, not
///    `fontSize`. That is the whole reason the previous font clipped.
///
/// Never returns less than the scaled [kToolbarHeight], so single-line screens
/// keep exactly the height they had.
double appBarHeightForTitle(BuildContext context, {int titleLines = 1}) {
  final scaler = MediaQuery.textScalerOf(context);
  final base = scaler.scale(kToolbarHeight);
  if (titleLines <= 1) return base;

  final theme = Theme.of(context);
  final style =
      theme.appBarTheme.titleTextStyle ?? theme.textTheme.headlineSmall;
  final fontSize = style?.fontSize;
  if (fontSize == null) return base;

  // Material's own clamp on AppBar title scaling.
  final titleScale = math.min(scaler.scale(fontSize) / fontSize, 1.34);
  final lineHeight = fontSize * titleScale * (style?.height ?? 1.0);

  return math.max(base, lineHeight * titleLines + Dimens.spacing8);
}

/// Builds the friendly-flat [ThemeData] for a palette. Component themes carry
/// the rounded shapes and flat surfaces so the look propagates app-wide; depth
/// lives in the [AppCard] widget rather than in heavy elevation here.
ThemeData buildAppTheme(AppPalette p) {
  final scheme = p.colorScheme;
  final text = appTextTheme(p);
  const pill = StadiumBorder();
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.canvas,
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Dimens.borderRadiusL,
        side: BorderSide(color: p.border, width: Dimens.hairline),
      ),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: p.canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.textStrong,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineSmall,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.accent.withValues(alpha: 0.16),
      elevation: 0,
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      indicatorShape: pill,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.accent,
      foregroundColor: p.onAccent,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        minimumSize: const Size(64, Dimens.minTouchTarget),
        shape: pill,
        textStyle: text.labelLarge,
        elevation: 0,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        textStyle: text.labelLarge,
        shape: pill,
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: p.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Dimens.spacing16,
        vertical: Dimens.spacing12,
      ),
      border: const OutlineInputBorder(
        borderRadius: Dimens.borderRadiusM,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: Dimens.borderRadiusM,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: Dimens.borderRadiusM,
        borderSide: BorderSide(color: p.accent, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      backgroundColor: p.surfaceMuted,
      side: BorderSide.none,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: Dimens.borderRadiusL),
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: Dimens.borderRadiusM),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Dimens.radiusXL),
        ),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
