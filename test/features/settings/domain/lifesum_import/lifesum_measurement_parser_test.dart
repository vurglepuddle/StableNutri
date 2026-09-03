import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_measurement_parser.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_measurement_preview.dart';

import '../../../../fixture/lifesum_export_fixture.dart';

void main() {
  group('LifesumMeasurementParser', () {
    test('parses the synthetic fixture and merges body fat by day', () {
      final result = LifesumMeasurementParser.parse(
        weighInsCsv: sanitizedLifesumFiles['weighins.csv']!,
        bodyMeasuresCsv: sanitizedLifesumFiles['bodymeasures.csv']!,
        bodyFatCsv: sanitizedLifesumFiles['bodyfat.csv']!,
      );

      expect(result.issues, isEmpty);
      expect(result.weights, hasLength(1));
      expect(result.weights.single.date, DateTime(2024, 1, 2));
      expect(result.weights.single.weightKg, 70);
      expect(result.bodyMeasurements, hasLength(1));
      expect(result.bodyMeasurements.single.waistCm, 80);
      expect(result.bodyMeasurements.single.bodyFatPercent, 20);
      expect(result.sourceRowsFor(LifesumExportSection.weighIns), 1);
      expect(result.sourceRowsFor(LifesumExportSection.bodyMeasures), 1);
      expect(result.sourceRowsFor(LifesumExportSection.bodyFat), 1);
    });

    test('normalizes supported measurement names and centimetre casing', () {
      const bodyMeasures =
          'date,measure,value,unit\n'
          '2024-02-03,waist,81,cm\n'
          '2024-02-03,Hip,92,Cm\n'
          '2024-02-03,CHEST,94,CM\n'
          '2024-02-03,arm,31,cm\n'
          '2024-02-03,thigh,54,cm\n'
          '2024-02-03,neck,37,cm\n';

      final result = LifesumMeasurementParser.parse(
        weighInsCsv: _emptyWeights,
        bodyMeasuresCsv: bodyMeasures,
        bodyFatCsv: _emptyBodyFat,
      );

      final measurement = result.bodyMeasurements.single;
      expect(measurement.waistCm, 81);
      expect(measurement.hipsCm, 92);
      expect(measurement.chestCm, 94);
      expect(measurement.armCm, 31);
      expect(measurement.thighCm, 54);
      expect(result.issues.map((issue) => issue.code), [
        LifesumMeasurementIssueCode.unsupportedMeasurement,
      ]);
    });

    test('collapses identical weights and omits an ambiguous weight day', () {
      const weights =
          'date,weight_kg,height_cm,goal_weight_kg\n'
          '2024-01-02,70,170,68\n'
          '2024-01-02,70,170,68\n'
          '2024-01-03,71,170,68\n'
          '2024-01-03,72,170,68\n';

      final result = LifesumMeasurementParser.parse(
        weighInsCsv: weights,
        bodyMeasuresCsv: _emptyBodyMeasures,
        bodyFatCsv: _emptyBodyFat,
      );

      expect(result.weights, hasLength(1));
      expect(result.weights.single.date, DateTime(2024, 1, 2));
      expect(result.issues.map((issue) => issue.code), [
        LifesumMeasurementIssueCode.duplicateSameDayValue,
        LifesumMeasurementIssueCode.conflictingSameDayValue,
      ]);
    });

    test('keeps other metrics when one same-day metric is ambiguous', () {
      const bodyMeasures =
          'date,measure,value,unit\n'
          '2024-01-02,waist,80,cm\n'
          '2024-01-02,waist,82,cm\n'
          '2024-01-02,hip,90,cm\n';

      final result = LifesumMeasurementParser.parse(
        weighInsCsv: _emptyWeights,
        bodyMeasuresCsv: bodyMeasures,
        bodyFatCsv: _emptyBodyFat,
      );

      expect(result.bodyMeasurements, hasLength(1));
      expect(result.bodyMeasurements.single.waistCm, isNull);
      expect(result.bodyMeasurements.single.hipsCm, 90);
      expect(
        result.issues.single.code,
        LifesumMeasurementIssueCode.conflictingSameDayValue,
      );
    });

    test('rejects invalid dates, values, units, and malformed rows safely', () {
      const weights =
          'date,weight_kg,height_cm,goal_weight_kg\n'
          '2024-02-30,70,170,68\n'
          '2024-01-03,NaN,170,68\n'
          '2024-01-04,1,170,68\n'
          '2024-01-05,70,170\n';
      const bodyMeasures =
          'date,measure,value,unit\n'
          '2024-01-02,waist,80,in\n'
          '2024-01-03,hip,Infinity,cm\n'
          '2024-01-04,arm,501,cm\n';
      const bodyFat =
          'date,bodyfat_pct\n'
          'not-a-date,20\n'
          '2024-01-02,101\n';

      final result = LifesumMeasurementParser.parse(
        weighInsCsv: weights,
        bodyMeasuresCsv: bodyMeasures,
        bodyFatCsv: bodyFat,
      );

      expect(result.weights, isEmpty);
      expect(result.bodyMeasurements, isEmpty);
      expect(result.warningCount, 9);
      expect(result.blockingIssueCount, 0);
      expect(result.issues.every((issue) => issue.rowNumber != null), isTrue);
    });

    test('a missing required header blocks only its source section', () {
      const weights = 'date,height_cm,goal_weight_kg\n2024-01-02,170,68\n';

      final result = LifesumMeasurementParser.parse(
        weighInsCsv: weights,
        bodyMeasuresCsv: sanitizedLifesumFiles['bodymeasures.csv']!,
        bodyFatCsv: sanitizedLifesumFiles['bodyfat.csv']!,
      );

      expect(result.weights, isEmpty);
      expect(result.bodyMeasurements, hasLength(1));
      expect(result.blockingIssueCount, 1);
      expect(result.issues.single.column, 'weight_kg');
      expect(result.issues.single.rowNumber, isNull);
    });
  });

  group('LifesumMeasurementPreview', () {
    test('keeps existing Stable days and exposes only missing candidates', () {
      const weights =
          'date,weight_kg,height_cm,goal_weight_kg\n'
          '2024-01-01,70,170,68\n'
          '2024-01-03,71,170,68\n';
      const bodyMeasures =
          'date,measure,value,unit\n'
          '2024-01-02,waist,80,cm\n'
          '2024-01-04,hip,90,cm\n';
      final result = LifesumMeasurementParser.parse(
        weighInsCsv: weights,
        bodyMeasuresCsv: bodyMeasures,
        bodyFatCsv: _emptyBodyFat,
      );

      final preview = LifesumMeasurementPreview.fromParseResult(
        result,
        existingWeights: <WeightLogEntity>[
          WeightLogEntity(date: DateTime(2024, 1, 1), weightKg: 75),
        ],
        existingBodyMeasurements: <BodyMeasurementLogEntity>[
          BodyMeasurementLogEntity(date: DateTime(2024, 1, 4), waistCm: 85),
        ],
      );

      expect(preview.sourceWeightRows, 2);
      expect(preview.sourceBodyMeasureRows, 2);
      expect(preview.weightCandidateCount, 2);
      expect(preview.bodyMeasurementCandidateCount, 2);
      expect(preview.existingWeightConflictCount, 1);
      expect(preview.existingBodyMeasurementConflictCount, 1);
      expect(preview.weightsToAdd.single.date, DateTime(2024, 1, 3));
      expect(preview.bodyMeasurementsToAdd.single.date, DateTime(2024, 1, 2));
      expect(preview.earliestCandidateDate, DateTime(2024, 1, 1));
      expect(preview.latestCandidateDate, DateTime(2024, 1, 4));
      expect(preview.readyToAddCount, 2);
      expect(preview.existingConflictCount, 2);
      expect(preview.canApply, isTrue);
    });

    test('can apply a valid section when another section is blocked', () {
      final result = LifesumMeasurementParser.parse(
        weighInsCsv: 'date,height_cm,goal_weight_kg\n2024-01-02,170,68\n',
        bodyMeasuresCsv: sanitizedLifesumFiles['bodymeasures.csv']!,
        bodyFatCsv: sanitizedLifesumFiles['bodyfat.csv']!,
      );

      final preview = LifesumMeasurementPreview.fromParseResult(result);

      expect(preview.hasBlockingIssues, isTrue);
      expect(preview.weightsToAdd, isEmpty);
      expect(preview.bodyMeasurementsToAdd, hasLength(1));
      expect(preview.canApply, isTrue);
    });
  });
}

const _emptyWeights = 'date,weight_kg,height_cm,goal_weight_kg\n';
const _emptyBodyMeasures = 'date,measure,value,unit\n';
const _emptyBodyFat = 'date,bodyfat_pct\n';
