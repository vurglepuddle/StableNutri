import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/scanner/util/gs1_gtin.dart';

/// GS is FNC1 as it reaches Dart, built explicitly so the source carries no
/// raw control byte.
const String gs = '\u001d';

void main() {
  group('gtinFromGs1', () {
    test('reads the GTIN from a real Chestny ZNAK DataMatrix', () {
      // Captured from a device scan. The same product's printed EAN-13 is
      // 4690388119119, which is exactly what this must resolve to.
      expect(
        gtinFromGs1('(01)04690388119119(21)5>.4OuogtX,0+(93)rjSl'),
        '4690388119119',
      );
    });

    test('reads the GTIN from an unbracketed element string', () {
      expect(gtinFromGs1('010469038811911921ABC123$gs'), '4690388119119');
    });

    test('reads a GTIN that is the only element', () {
      expect(gtinFromGs1('(01)04690388119119'), '4690388119119');
    });

    test('finds AI 01 after a separator, not only at the start', () {
      expect(
        gtinFromGs1(
          '10BATCH7$gs'
          '0104690388119119',
        ),
        '4690388119119',
      );
    });

    group('rejects', () {
      test('a plain EAN-13, which is not a GS1 element string', () {
        expect(gtinFromGs1('4690388119119'), isNull);
      });

      test('a URL from an ordinary QR code', () {
        expect(
          gtinFromGs1('https://example.org/product/01/12345678901234'),
          isNull,
        );
      });

      test('an empty string', () => expect(gtinFromGs1(''), isNull));

      test('a GTIN whose check digit is wrong', () {
        // Same code as the working case with the check digit changed 9 -> 8.
        expect(gtinFromGs1('(01)04690388119118'), isNull);
      });

      test('a case-level GTIN, which is not the consumer unit', () {
        // Indicator digit 1 means an outer case. Looking it up would return
        // the wrong product or nothing, so it must not reach the barcode path.
        expect(gtinFromGs1('(01)14690388119116'), isNull);
      });

      test('a variable-measure GTIN (indicator 9)', () {
        // Check digit 2 is correct here, so this is rejected for the indicator
        // rather than incidentally failing validation.
        expect(gtinFromGs1('(01)94690388119112'), isNull);
      });

      test('AI 01 with too few digits to be a GTIN-14', () {
        expect(gtinFromGs1('(01)0469038811'), isNull);
      });

      test('digits that merely look like AI 01 inside a serial', () {
        // AI 21's value contains "01" followed by 14 digits. Because AI 01 is
        // only recognised at the start of a segment, this must not match.
        expect(gtinFromGs1('(21)0104690388119119'), isNull);
      });
    });
  });
}
