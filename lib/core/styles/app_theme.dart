import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

/// Friendly, highly readable type. Biryani carries everything — warm and open
/// without being cute, and calm enough to stay legible in dense lists. Heavy
/// weights give the hero numbers presence without a separate display face; Ovo
/// appears only in the logo, where it is already outlined into paths.
///
/// Biryani has **no Medium (500) and no italics** — its ladder is
/// 200/300/400/600/700/800/900. Body text therefore sits at w400 rather than
/// the w500 the Nunito scale used; asking for 500 would silently resolve to a
/// neighbouring face and differ between platforms.
///
/// The weights are also a notch lighter than the Nunito scale they replaced
/// (800 became 700, 700 became 600, throughout the app and not just here).
/// Biryani carries more colour on the page at the same numeric weight, and the
/// inherited ladder read as shouting. Nothing above w700 is used: w800 and
/// w900 exist in the family but overwhelm this layout.
/// Line heights are set explicitly on every style, and must stay that way.
///
/// Biryani is a Devanagari family: its vertical metrics carry room for marks
/// above *and* below the baseline, so its intrinsic line box is **1.78x** the
/// font size. Measured against the same string at the same size, Poppins is
/// 1.48x and the Nunito this replaced was 1.35x — so adopting Biryani made
/// every line in the app 32% taller overnight, with nothing to compensate.
///
/// Left unset it shows up as gaping leading between wrapped lines and, worse,
/// as clipped text in any fixed-height box. At 1.78x a 23 px title is a 41 px
/// line, so a two-line AppBar title needs 82 px in a 56 px toolbar and loses
/// the top and bottom of both lines.
///
/// A *single*-line title survives, but only by accident of the framework:
/// Material's AppBar clamps title text scaling at 1.34, which caps a 1.78x
/// line at 54.9 px — just inside 56. Do not rely on that. It is why the
/// one-line cases in app_bar_title_scaling_test pass either way, and it means
/// the clamp, not our type scale, is currently holding those titles up.
///
/// This app is used at a raised system font scale for accessibility, so
/// anything that only fits at 1.0 is broken in normal use. See "Type scale and
/// text scaling" in Design/session-handoff.md.
///
/// The ladder below is deliberately tighter than the Material 3 ratios
/// (which put headlineSmall at 1.33). M3's value needs 61 px for two lines and
/// would still clip a wrapped AppBar title without also growing every toolbar.
const _displayHeight = 1.12;
const _headlineHeight = 1.15;
const _titleHeight = 1.20;
const _bodyHeight = 1.40;
const _labelHeight = 1.30;

TextTheme appTextTheme(AppPalette p) {
  const f = 'Biryani';
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
