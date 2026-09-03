import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_measurement_parser.dart';

/// Conflict-aware preview for the default "add missing, keep existing" policy.
class LifesumMeasurementPreview {
  LifesumMeasurementPreview._({
    required this.sourceWeightRows,
    required this.sourceBodyMeasureRows,
    required this.sourceBodyFatRows,
    required this.weightCandidateCount,
    required this.bodyMeasurementCandidateCount,
    required this.existingWeightConflictCount,
    required this.existingBodyMeasurementConflictCount,
    required this.earliestCandidateDate,
    required this.latestCandidateDate,
    required this.blockingIssueCount,
    required this.warningCount,
    required List<WeightLogEntity> weightsToAdd,
    required List<BodyMeasurementLogEntity> bodyMeasurementsToAdd,
    required List<LifesumMeasurementIssue> issues,
  }) : weightsToAdd = List<WeightLogEntity>.unmodifiable(weightsToAdd),
       bodyMeasurementsToAdd = List<BodyMeasurementLogEntity>.unmodifiable(
         bodyMeasurementsToAdd,
       ),
       issues = List<LifesumMeasurementIssue>.unmodifiable(issues);

  factory LifesumMeasurementPreview.fromParseResult(
    LifesumMeasurementParseResult result, {
    Iterable<WeightLogEntity> existingWeights = const <WeightLogEntity>[],
    Iterable<BodyMeasurementLogEntity> existingBodyMeasurements =
        const <BodyMeasurementLogEntity>[],
  }) {
    final existingWeightDays = existingWeights.map(_dayKey).toSet();
    final existingBodyDays = existingBodyMeasurements.map(_dayKey).toSet();
    final weightsToAdd = result.weights
        .where((entry) => !existingWeightDays.contains(_dayKey(entry)))
        .toList();
    final bodyMeasurementsToAdd = result.bodyMeasurements
        .where((entry) => !existingBodyDays.contains(_dayKey(entry)))
        .toList();

    final candidateDates = <DateTime>[
      ...result.weights.map((entry) => entry.date),
      ...result.bodyMeasurements.map((entry) => entry.date),
    ]..sort();

    return LifesumMeasurementPreview._(
      sourceWeightRows: result.sourceRowsFor(LifesumExportSection.weighIns),
      sourceBodyMeasureRows: result.sourceRowsFor(
        LifesumExportSection.bodyMeasures,
      ),
      sourceBodyFatRows: result.sourceRowsFor(LifesumExportSection.bodyFat),
      weightCandidateCount: result.weights.length,
      bodyMeasurementCandidateCount: result.bodyMeasurements.length,
      existingWeightConflictCount: result.weights.length - weightsToAdd.length,
      existingBodyMeasurementConflictCount:
          result.bodyMeasurements.length - bodyMeasurementsToAdd.length,
      earliestCandidateDate: candidateDates.isEmpty
          ? null
          : candidateDates.first,
      latestCandidateDate: candidateDates.isEmpty ? null : candidateDates.last,
      blockingIssueCount: result.blockingIssueCount,
      warningCount: result.warningCount,
      weightsToAdd: weightsToAdd,
      bodyMeasurementsToAdd: bodyMeasurementsToAdd,
      issues: result.issues,
    );
  }

  final int sourceWeightRows;
  final int sourceBodyMeasureRows;
  final int sourceBodyFatRows;
  final int weightCandidateCount;
  final int bodyMeasurementCandidateCount;
  final int existingWeightConflictCount;
  final int existingBodyMeasurementConflictCount;
  final DateTime? earliestCandidateDate;
  final DateTime? latestCandidateDate;
  final int blockingIssueCount;
  final int warningCount;
  final List<WeightLogEntity> weightsToAdd;
  final List<BodyMeasurementLogEntity> bodyMeasurementsToAdd;
  final List<LifesumMeasurementIssue> issues;

  int get candidateCount =>
      weightCandidateCount + bodyMeasurementCandidateCount;

  int get existingConflictCount =>
      existingWeightConflictCount + existingBodyMeasurementConflictCount;

  int get readyToAddCount => weightsToAdd.length + bodyMeasurementsToAdd.length;

  bool get hasBlockingIssues => blockingIssueCount > 0;

  /// A malformed source section is omitted by the parser, but does not block
  /// valid candidates produced by either of the other measurement sections.
  bool get canApply => readyToAddCount > 0;

  static int _dayKey(Object entry) {
    final date = switch (entry) {
      WeightLogEntity value => value.date,
      BodyMeasurementLogEntity value => value.date,
      _ => throw ArgumentError.value(entry, 'entry'),
    };
    return date.year * 10000 + date.month * 100 + date.day;
  }
}
