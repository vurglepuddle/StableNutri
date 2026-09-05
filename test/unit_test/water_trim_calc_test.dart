import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/utils/calc/water_trim_calc.dart';

WaterIntakeEntity _entry(String id, int hour, int ml) => WaterIntakeEntity(
  id: id,
  dateTime: DateTime(2026, 9, 5, hour),
  amountMl: ml,
);

void main() {
  test('removing a cup drops the newest drink when the sizes match', () {
    final trim = WaterTrimCalc.trim([
      _entry('a', 8, 250),
      _entry('b', 12, 250),
    ], 250);
    expect(trim.deleteIds, ['b']);
    expect(trim.reducedAt, isNull);
    expect(trim.reducedMl, 0);
  });

  test('a drink larger than the cup is reduced, not deleted', () {
    final trim = WaterTrimCalc.trim([_entry('bottle', 9, 700)], 250);
    expect(trim.deleteIds, ['bottle']);
    expect(trim.reducedAt, DateTime(2026, 9, 5, 9));
    expect(trim.reducedMl, 450);
  });

  test('one cup can span several small drinks, newest first', () {
    final trim = WaterTrimCalc.trim([
      _entry('a', 7, 400),
      _entry('b', 8, 100),
      _entry('c', 9, 100),
    ], 250);
    expect(trim.deleteIds, ['c', 'b', 'a']);
    expect(trim.reducedAt, DateTime(2026, 9, 5, 7));
    expect(trim.reducedMl, 350);
  });

  test('unsorted input is ordered by time before trimming', () {
    final trim = WaterTrimCalc.trim([
      _entry('late', 20, 250),
      _entry('early', 6, 250),
    ], 250);
    expect(trim.deleteIds, ['late']);
  });

  test(
    'removing more than the day holds empties it without going negative',
    () {
      final trim = WaterTrimCalc.trim([
        _entry('a', 8, 100),
        _entry('b', 9, 100),
      ], 500);
      expect(trim.deleteIds, ['b', 'a']);
      expect(trim.reducedAt, isNull);
      expect(trim.reducedMl, 0);
    },
  );

  test('nothing to remove is reported as an empty trim', () {
    expect(WaterTrimCalc.trim(const [], 250).isEmpty, isTrue);
    expect(WaterTrimCalc.trim([_entry('a', 8, 250)], 0).isEmpty, isTrue);
    expect(WaterTrimCalc.trim([_entry('a', 8, 250)], -250).isEmpty, isTrue);
  });
}
