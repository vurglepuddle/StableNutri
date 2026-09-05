import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/water_format.dart';

void main() {
  test('litres round to one decimal and drop a redundant .0', () {
    expect(WaterFormat.litresText(0, locale: 'en'), '0');
    expect(WaterFormat.litresText(250, locale: 'en'), '0.3');
    expect(WaterFormat.litresText(1200, locale: 'en'), '1.2');
    expect(WaterFormat.litresText(1250, locale: 'en'), '1.3');
    expect(WaterFormat.litresText(2000, locale: 'en'), '2');
    expect(WaterFormat.litresText(2500, locale: 'en'), '2.5');
    expect(WaterFormat.litresText(10000, locale: 'en'), '10');
  });

  test('the decimal mark follows the locale', () {
    expect(WaterFormat.litresText(1200, locale: 'de'), '1,2');
    expect(WaterFormat.decimalSeparator('de'), ',');
    expect(WaterFormat.decimalSeparator('en'), '.');
  });

  test('litres is a plain millilitre conversion', () {
    expect(WaterFormat.litres(0), 0);
    expect(WaterFormat.litres(1500), 1.5);
  });
}
