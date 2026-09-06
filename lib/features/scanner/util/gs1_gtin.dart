import 'package:opennutritracker/features/scanner/util/barcode_check_digit.dart';

/// Extracts the consumer-unit barcode from a GS1 element string.
///
/// GS1 DataMatrix is now printed on a lot of packaging — pharmaceuticals,
/// alcohol and tobacco across the EU, and everything under Russia's Chestny
/// ZNAK scheme — usually alongside, or instead of, a plain EAN-13. The symbol
/// does not encode a bare barcode: it encodes a sequence of
/// Application Identifier / value pairs, of which AI `01` is the GTIN:
///
///     (01)04690388119119(21)5>.4OuogtX,0+(93)rjSl
///      \__/\____________/
///       AI      GTIN-14
///
/// Returns the GTIN as EAN-13, which is the form the same product's linear
/// barcode would carry and therefore the form Open Food Facts is keyed on.
/// Returns null for anything that is not a GS1 string with a usable
/// consumer-unit GTIN, which is the signal to ignore the code.
String? gtinFromGs1(String raw) {
  final gtin14 = _findGtin14(raw);
  if (gtin14 == null) return null;

  // The leading digit of a GTIN-14 is the packaging indicator. Only `0` marks
  // the consumer unit; `1`-`8` identify case and pallet levels and `9` marks a
  // variable-measure trade item. None of those name the thing on a plate, and
  // looking them up would silently return the wrong product or nothing at all.
  if (!gtin14.startsWith('0')) return null;

  final ean13 = gtin14.substring(1);
  // The check digit survives dropping the leading zero — it contributes zero to
  // the weighted sum either way — so validating the returned form is enough.
  if (!isValidBarcodeCheckDigit(ean13)) return null;
  return ean13;
}

/// FNC1, which a GS1 element string uses to terminate a variable-length field.
/// It reaches Dart as the GS control character, written here as an escape
/// so the source carries no raw control byte.
const String _groupSeparator = '\u001d';

final RegExp _bracketedGtin = RegExp(r'\(01\)(\d{14})');
final RegExp _fourteenDigits = RegExp(r'^\d{14}$');

String? _findGtin14(String raw) {
  // The bracketed human-readable form, which is what zxing-cpp emits for a
  // symbol carrying a GS1 FNC1 indicator.
  final match = _bracketedGtin.firstMatch(raw);
  if (match != null) return match.group(1);

  // The unbracketed form, where AIs run together with no delimiter and only
  // variable-length fields are separated. AI `01` is fixed-length, so it can
  // only appear at the very start or immediately after a separator — searching
  // for "01" anywhere would happily match digits inside a serial number.
  for (final String segment in raw.split(_groupSeparator)) {
    if (segment.length < 16 || !segment.startsWith('01')) continue;
    final String candidate = segment.substring(2, 16);
    if (_fourteenDigits.hasMatch(candidate)) return candidate;
  }
  return null;
}
