import 'package:intl/intl.dart';

/// Nobody drinks "1,750 millilitres" — they drink "1.8 l". Water totals are
/// shown in litres with a single decimal (the reference the redesign follows),
/// while individual drinks stay in millilitres, which is how glass and bottle
/// sizes are actually chosen. Storage stays in millilitres throughout; this is
/// a display concern only.
abstract final class WaterFormat {
  static const int mlPerLitre = 1000;

  static double litres(int ml) => ml / mlPerLitre;

  /// The localized decimal separator, so `AnimatedFlipCounter` prints "1,2 l"
  /// in de/cs/pl and "1.2 l" in en without us hand-rolling a locale table.
  static String decimalSeparator([String? locale]) =>
      NumberFormat.decimalPattern(
        locale ?? Intl.getCurrentLocale(),
      ).symbols.DECIMAL_SEP;

  /// Whole litres lose the decimal ("2 l", not "2.0 l") so a round goal reads
  /// as the round number the user typed. Everything else keeps one decimal.
  static String litresText(int ml, {String? locale}) {
    final value = litres(ml);
    final rounded = (value * 10).round() / 10;
    final digits = rounded == rounded.roundToDouble() ? 0 : 1;
    return NumberFormat.decimalPatternDigits(
      locale: locale ?? Intl.getCurrentLocale(),
      decimalDigits: digits,
    ).format(rounded);
  }
}
