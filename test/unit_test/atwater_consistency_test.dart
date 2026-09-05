import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

MealNutrimentsEntity _n({
  double? energy,
  double? carbs,
  double? fat,
  double? protein,
}) => MealNutrimentsEntity(
  energyKcal100: energy,
  carbohydrates100: carbs,
  fat100: fat,
  proteins100: protein,
  sugars100: null,
  saturatedFat100: null,
  fiber100: null,
);

void main() {
  group('Atwater energy consistency', () {
    test('coherent product has a small relative error and is consistent', () {
      // 4*10 + 4*5 + 9*5 = 105 vs declared 100 -> 5% error.
      final n = _n(energy: 100, carbs: 10, fat: 5, protein: 5);
      expect(atwaterEnergyRelativeError(n)! < 0.10, isTrue);
      expect(isAtwaterConsistent(n), isTrue);
    });

    test('declared kcal far above macro-implied energy is inconsistent', () {
      // macros imply 4*5 + 4*1 + 9*1 = 33 vs declared 100 -> 67% error.
      final n = _n(energy: 100, carbs: 5, fat: 1, protein: 1);
      expect(atwaterEnergyRelativeError(n)! > atwaterEnergyTolerance, isTrue);
      expect(isAtwaterConsistent(n), isFalse);
    });

    test('a unit slip (kJ logged as kcal) is caught', () {
      // ~2252 kJ stored where kcal expected, against ~540 kcal of macros.
      final n = _n(energy: 2252, carbs: 57, fat: 31, protein: 6);
      expect(isAtwaterConsistent(n), isFalse);
    });

    test('no declared energy -> no opinion (treated as consistent)', () {
      final n = _n(energy: null, carbs: 10, fat: 5, protein: 5);
      expect(atwaterEnergyRelativeError(n), isNull);
      expect(isAtwaterConsistent(n), isTrue);
    });

    test('no macros at all -> no opinion (treated as consistent)', () {
      final n = _n(energy: 200);
      expect(atwaterEnergyRelativeError(n), isNull);
      expect(isAtwaterConsistent(n), isTrue);
    });

    test('boundary just under 25% stays consistent', () {
      // declared 100, macros imply 4*15+4*5+9*5 = 125 -> 25% over; nudge under.
      final n = _n(energy: 100, carbs: 14, fat: 5, protein: 5);
      // 4*14+4*5+9*5 = 121 -> 21% -> consistent.
      expect(isAtwaterConsistent(n), isTrue);
    });
  });
}
