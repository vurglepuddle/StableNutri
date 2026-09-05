import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';

void main() {
  group('UnitDropdownItem Enum Tests', () {
    test('toString() returns correct string representation', () {
      expect(UnitDropdownItem.g.toString(), 'g');
      expect(UnitDropdownItem.ml.toString(), 'ml');
      expect(UnitDropdownItem.gml.toString(), 'g/ml');
      expect(UnitDropdownItem.oz.toString(), 'oz');
      expect(UnitDropdownItem.flOz.toString(), 'fl.oz');
      expect(UnitDropdownItem.serving.toString(), 'serving');
    });

    group('fromString()', () {
      test('returns correct enum for standard cases', () {
        expect(UnitDropdownItem.g.fromString('g'), UnitDropdownItem.g);
        expect(UnitDropdownItem.ml.fromString('ml'), UnitDropdownItem.ml);
        expect(UnitDropdownItem.gml.fromString('g/ml'), UnitDropdownItem.gml);
        expect(UnitDropdownItem.oz.fromString('oz'), UnitDropdownItem.oz);
        expect(
          UnitDropdownItem.serving.fromString('serving'),
          UnitDropdownItem.serving,
        );
      });

      test('handles fl oz variations correctly', () {
        expect(
          UnitDropdownItem.flOz.fromString('fl oz'),
          UnitDropdownItem.flOz,
        );
        expect(
          UnitDropdownItem.flOz.fromString('fl.oz'),
          UnitDropdownItem.flOz,
        );
      });

      test('returns gml as default for unknown values', () {
        expect(UnitDropdownItem.g.fromString('unknown'), UnitDropdownItem.gml);
        expect(UnitDropdownItem.g.fromString(''), UnitDropdownItem.gml);
        expect(UnitDropdownItem.g.fromString('123'), UnitDropdownItem.gml);
      });

      test('is case sensitive', () {
        expect(UnitDropdownItem.g.fromString('G'), UnitDropdownItem.gml);
        expect(UnitDropdownItem.ml.fromString('ML'), UnitDropdownItem.gml);
      });
    });
  });
}
