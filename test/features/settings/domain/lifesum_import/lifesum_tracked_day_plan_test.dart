import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_manifest.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_preview.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_tracked_day_plan.dart';

import '../../../../fixture/lifesum_export_fixture.dart';

void main() {
  late Directory temporaryDirectory;
  late LifesumArchiveCsvSelection selection;
  late LifesumImportPreview preview;
  late LifesumImportManifest manifest;
  late LifesumHistoricalGoalSnapshot goals;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'stable_lifesum_tracked_day_',
    );
    final zip = writeSanitizedLifesumZip(temporaryDirectory);
    selection = const LifesumArchiveReader().readCsvSectionsPath(
      zip.path,
      LifesumExportSection.values.toSet(),
    );
    preview = LifesumImportPreview.fromSelection(selection);
    manifest = LifesumImportManifest.fromPreview(preview);
    goals = LifesumHistoricalGoalSnapshot(
      calorieGoal: 2000,
      carbsGoal: 300,
      fatGoal: 55,
      proteinGoal: 75,
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  group('LifesumTrackedDayPlan', () {
    test('combines intake totals with Stable activity goal adjustments', () {
      final plan = LifesumTrackedDayPlan.fromManifest(manifest, goals: goals);

      expect(
        plan.policy,
        LifesumHistoricalGoalPolicy.copyCurrentProfileTargets,
      );
      expect(plan.sourceAffectedDayCount, 1);
      expect(plan.existingDayCount, 0);
      expect(plan.candidateDayCount, 1);
      expect(plan.canCompleteManifest, isTrue);
      final entry = plan.entries.single;
      expect(entry.intakeCount, 1);
      expect(entry.activityCount, 1);
      expect(entry.activityCaloriesBurned, 120);
      expect(entry.trackedDay.day, DateTime(2024, 1, 2));
      expect(entry.trackedDay.calorieGoal, 2120);
      expect(entry.trackedDay.caloriesTracked, closeTo(300, 0.000001));
      expect(entry.trackedDay.carbsGoal, closeTo(318, 0.000001));
      expect(entry.trackedDay.carbsTracked, closeTo(50, 0.000001));
      expect(entry.trackedDay.fatGoal, closeTo(58.333333, 0.000001));
      expect(entry.trackedDay.fatTracked, closeTo(6, 0.000001));
      expect(entry.trackedDay.proteinGoal, closeTo(79.5, 0.000001));
      expect(entry.trackedDay.proteinTracked, closeTo(10, 0.000001));
    });

    test('completes the manifest before primary diary operations', () {
      final plan = LifesumTrackedDayPlan.fromManifest(manifest, goals: goals);

      final completed = plan.completeManifest(manifest);

      expect(completed.manifestId, isNot(manifest.manifestId));
      expect(completed.requiresTrackedDayPolicy, isFalse);
      expect(completed.isExecutable, isTrue);
      expect(completed.operationCount, manifest.operationCount + 1);
      expect(
        completed.operations.map((operation) => operation.kind),
        <LifesumImportOperationKind>[
          LifesumImportOperationKind.weight,
          LifesumImportOperationKind.bodyMeasurement,
          LifesumImportOperationKind.trackedDay,
          LifesumImportOperationKind.intake,
          LifesumImportOperationKind.activity,
        ],
      );
    });

    test('blocks stale primary operations on an existing tracked day', () {
      final existing = TrackedDayEntity(
        day: DateTime(2024, 1, 2),
        calorieGoal: 1800,
        caloriesTracked: 100,
      );
      final stalePlan = LifesumTrackedDayPlan.fromManifest(
        manifest,
        goals: goals,
        existingTrackedDays: <TrackedDayEntity>[existing],
      );

      expect(stalePlan.existingDayCount, 1);
      expect(stalePlan.entries, isEmpty);
      expect(stalePlan.canCompleteManifest, isFalse);
      expect(() => stalePlan.completeManifest(manifest), throwsStateError);

      final refreshedPreview = LifesumImportPreview.fromSelection(
        selection,
        existingTrackedDays: <TrackedDayEntity>[existing],
      );
      final refreshedManifest = LifesumImportManifest.fromPreview(
        refreshedPreview,
      );
      expect(refreshedPreview.food?.occupiedDayConflictCount, 1);
      expect(refreshedPreview.activity?.occupiedDayConflictCount, 1);
      expect(refreshedManifest.requiresTrackedDayPolicy, isFalse);
      expect(
        refreshedManifest.operationCountFor(LifesumImportOperationKind.intake),
        0,
      );
      expect(
        refreshedManifest.operationCountFor(
          LifesumImportOperationKind.activity,
        ),
        0,
      );
    });

    test('supports an activity-only day with zero tracked intake', () {
      final activityOnly = LifesumImportManifest.fromPreview(
        preview,
        selection: const LifesumImportSelection(
          includeFood: false,
          includeWeights: false,
          includeBodyMeasurements: false,
        ),
      );

      final plan = LifesumTrackedDayPlan.fromManifest(
        activityOnly,
        goals: goals,
      );

      final day = plan.entries.single.trackedDay;
      expect(day.calorieGoal, 2120);
      expect(day.caloriesTracked, 0);
      expect(day.carbsTracked, 0);
      expect(day.fatTracked, 0);
      expect(day.proteinTracked, 0);
    });

    test('rejects invalid goals and completion with a different manifest', () {
      expect(
        () => LifesumHistoricalGoalSnapshot(
          calorieGoal: 0,
          carbsGoal: 300,
          fatGoal: 55,
          proteinGoal: 75,
        ),
        throwsArgumentError,
      );
      expect(
        () => LifesumHistoricalGoalSnapshot(
          calorieGoal: 2000,
          carbsGoal: double.nan,
          fatGoal: 55,
          proteinGoal: 75,
        ),
        throwsArgumentError,
      );

      final plan = LifesumTrackedDayPlan.fromManifest(manifest, goals: goals);
      final otherManifest = LifesumImportManifest.fromPreview(
        preview,
        selection: const LifesumImportSelection(includeFood: false),
      );
      expect(() => plan.completeManifest(otherManifest), throwsStateError);
    });
  });
}
