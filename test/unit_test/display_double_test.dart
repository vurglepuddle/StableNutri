import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/extensions.dart';

/// Edit fields showed raw doubles: unit conversions left values like
/// 2.000000000000004 g of protein.
void main() {
  test('float noise is trimmed', () {
    expect(2.000000000000004.toStringOrEmpty(), '2');
    expect((0.1 + 0.2).toStringOrEmpty(), '0.3');
  });

  test('real decimals and tiny amounts are kept', () {
    expect(12.5.toStringOrEmpty(), '12.5');
    expect(0.000005.toStringOrEmpty(), '0.000005');
  });

  test('null stays empty and whole numbers drop ".0"', () {
    expect((null as double?).toStringOrEmpty(), '');
    expect(100.0.toStringOrEmpty(), '100');
  });
}
