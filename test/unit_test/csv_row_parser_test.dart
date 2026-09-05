import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/csv_row_parser.dart';

void main() {
  group('CsvRowParser.splitRow', () {
    test('plain comma-separated fields', () {
      expect(CsvRowParser.splitRow('a,b,c'), ['a', 'b', 'c']);
    });

    test('quoted field with embedded comma', () {
      expect(CsvRowParser.splitRow('a,"b,c",d'), ['a', 'b,c', 'd']);
    });

    test('escaped double-quote inside a quoted field', () {
      expect(CsvRowParser.splitRow('a,"He said ""hi""",b'), [
        'a',
        'He said "hi"',
        'b',
      ]);
    });

    test('trailing empty field', () {
      expect(CsvRowParser.splitRow('a,b,'), ['a', 'b', '']);
    });

    test('decimal-comma must be quoted to stay in one field', () {
      // Documents the rule the importer error message points to.
      expect(CsvRowParser.splitRow('1,5,g'), ['1', '5', 'g']);
      expect(CsvRowParser.splitRow('"1,5",g'), ['1,5', 'g']);
    });
  });

  group('CsvRowParser.parseDoubleOrNull', () {
    test('plain double parses', () {
      expect(CsvRowParser.parseDoubleOrNull('3.14'), 3.14);
    });

    test('comma decimal parses too', () {
      expect(CsvRowParser.parseDoubleOrNull('3,14'), 3.14);
    });

    test('leading and trailing whitespace is trimmed', () {
      expect(CsvRowParser.parseDoubleOrNull('  42 '), 42.0);
    });

    test('empty and null inputs return null', () {
      expect(CsvRowParser.parseDoubleOrNull(null), isNull);
      expect(CsvRowParser.parseDoubleOrNull(''), isNull);
      expect(CsvRowParser.parseDoubleOrNull('   '), isNull);
    });

    test('non-numeric returns null', () {
      expect(CsvRowParser.parseDoubleOrNull('abc'), isNull);
    });
  });
}
