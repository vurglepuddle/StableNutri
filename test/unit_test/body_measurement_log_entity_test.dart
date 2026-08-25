import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/features/measurements/presentation/utils/body_measurement_format.dart';

void main() {
  group('BodyMeasurementLogEntity', () {
    test('accepts partial snapshots and resolves values by type', () {
      final entry = BodyMeasurementLogEntity(
        date: DateTime(2026, 8, 20),
        waistCm: 80,
        bodyFatPercent: 22,
      );

      expect(entry.isValid, isTrue);
      expect(entry.valueFor(BodyMeasurementType.waist), 80);
      expect(entry.valueFor(BodyMeasurementType.hips), isNull);
      expect(entry.valueFor(BodyMeasurementType.bodyFat), 22);
    });

    test('requires one measurement and rejects invalid bounds', () {
      expect(BodyMeasurementLogEntity(date: DateTime(2026)).isValid, isFalse);
      expect(
        BodyMeasurementLogEntity(
          date: DateTime(2026),
          waistCm: double.nan,
        ).isValid,
        isFalse,
      );
      expect(
        BodyMeasurementLogEntity(
          date: DateTime(2026),
          bodyFatPercent: 101,
        ).isValid,
        isFalse,
      );
    });
  });

  group('body measurement formatting', () {
    test('round-trips inches through canonical centimetres', () {
      final cm = bodyMeasurementFromDisplay(31.5, true);
      expect(cm, closeTo(80.01, 0.001));
      expect(bodyMeasurementToDisplay(cm, true), closeTo(31.5, 0.001));
    });

    test('formats lengths and body fat with the correct unit', () {
      expect(
        formatBodyMeasurementValue(
          80,
          BodyMeasurementType.waist,
          imperial: false,
          cmLabel: 'cm',
          inLabel: 'in',
        ),
        '80 cm',
      );
      expect(
        formatBodyMeasurementValue(
          21.3,
          BodyMeasurementType.bodyFat,
          imperial: true,
          cmLabel: 'cm',
          inLabel: 'in',
        ),
        '21.3%',
      );
    });
  });
}
