import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_journal.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_manifest.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_preview.dart';

import '../../../../fixture/lifesum_export_fixture.dart';

void main() {
  late Directory temporaryDirectory;
  late LifesumImportPreview preview;
  late LifesumImportManifest manifest;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'stable_lifesum_manifest_',
    );
    final zip = writeSanitizedLifesumZip(temporaryDirectory);
    final selection = const LifesumArchiveReader().readCsvSectionsPath(
      zip.path,
      LifesumExportSection.values.toSet(),
    );
    preview = LifesumImportPreview.fromSelection(selection);
    manifest = LifesumImportManifest.fromPreview(preview);
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  group('LifesumImportManifest', () {
    test('freezes only conflict-free supported payloads in stable order', () {
      expect(manifest.operationCount, 4);
      expect(
        manifest.operations.map((operation) => operation.kind),
        <LifesumImportOperationKind>[
          LifesumImportOperationKind.weight,
          LifesumImportOperationKind.bodyMeasurement,
          LifesumImportOperationKind.intake,
          LifesumImportOperationKind.activity,
        ],
      );
      expect(manifest.operations[0], isA<LifesumWeightImportOperation>());
      expect(
        manifest.operations[1],
        isA<LifesumBodyMeasurementImportOperation>(),
      );
      expect(manifest.operations[2], isA<LifesumIntakeImportOperation>());
      expect(manifest.operations[3], isA<LifesumActivityImportOperation>());
      expect(manifest.operationCountFor(LifesumImportOperationKind.intake), 1);
      expect(manifest.includesEstimatedData, isFalse);
      expect(manifest.requiresTrackedDayPolicy, isTrue);
      expect(manifest.affectedTrackedDays, <DateTime>[DateTime(2024, 1, 2)]);
      expect(manifest.manifestId, startsWith('lifesum-manifest-'));
      expect(manifest.manifestId, isNot(contains('Example')));
    });

    test('includes estimated water only after explicit selection', () {
      final waterOnly = LifesumImportManifest.fromPreview(
        preview,
        selection: const LifesumImportSelection(
          includeFood: false,
          includeActivity: false,
          includeWeights: false,
          includeBodyMeasurements: false,
          includeEstimatedWater: true,
        ),
      );

      expect(waterOnly.operationCount, 1);
      expect(
        waterOnly.operations.single,
        isA<LifesumEstimatedWaterImportOperation>(),
      );
      expect(waterOnly.includesEstimatedData, isTrue);
      expect(waterOnly.requiresTrackedDayPolicy, isFalse);
    });

    test('has a deterministic identity for the same preview and choices', () {
      final repeated = LifesumImportManifest.fromPreview(preview);
      final withWater = LifesumImportManifest.fromPreview(
        preview,
        selection: const LifesumImportSelection(includeEstimatedWater: true),
      );

      expect(repeated.manifestId, manifest.manifestId);
      expect(
        repeated.operations.map((operation) => operation.operationId),
        manifest.operations.map((operation) => operation.operationId),
      );
      expect(withWater.manifestId, isNot(manifest.manifestId));
    });

    test('daily target identity changes when its private payload changes', () {
      final first = LifesumWeightImportOperation(
        WeightLogEntity(
          date: DateTime(2024, 1, 2),
          weightKg: 70,
          note: 'private marker',
        ),
      );
      final revised = LifesumWeightImportOperation(
        WeightLogEntity(
          date: DateTime(2024, 1, 2),
          weightKg: 71,
          note: 'private marker',
        ),
      );

      expect(first.targetKey, revised.targetKey);
      expect(first.operationId, isNot(revised.operationId));
      expect(first.operationId, isNot(contains('private marker')));
    });

    test('a rerun preview produces no duplicate operations', () {
      final rerunPreview = LifesumImportPreview.fromSelection(
        const LifesumArchiveReader().readCsvSectionsPath(
          writeSanitizedLifesumZip(temporaryDirectory).path,
          LifesumExportSection.values.toSet(),
        ),
        existingIntakes: preview.food!.parseResult.intakes,
        existingActivities: preview.activity!.parseResult.activities,
        existingWeights: preview.measurements!.weightsToAdd,
        existingBodyMeasurements: preview.measurements!.bodyMeasurementsToAdd,
        existingWaterEntries: preview.estimatedWater!.candidates,
      );

      final rerunManifest = LifesumImportManifest.fromPreview(
        rerunPreview,
        selection: const LifesumImportSelection(includeEstimatedWater: true),
      );

      expect(rerunManifest.operations, isEmpty);
      expect(rerunManifest.requiresTrackedDayPolicy, isFalse);
    });

    test('carries the sanitized preview day boundary into every operation', () {
      final zip = writeSanitizedLifesumZip(temporaryDirectory);
      final selection = const LifesumArchiveReader().readCsvSectionsPath(
        zip.path,
        LifesumExportSection.values.toSet(),
      );
      final invalidOffsetPreview = LifesumImportPreview.fromSelection(
        selection,
        dayStartOffsetMinutes: 24 * 60,
      );
      final invalidOffsetManifest = LifesumImportManifest.fromPreview(
        invalidOffsetPreview,
      );

      expect(invalidOffsetPreview.dayStartOffsetMinutes, 0);
      expect(invalidOffsetManifest.dayStartOffsetMinutes, 0);
      expect(invalidOffsetManifest.affectedTrackedDays, <DateTime>[
        DateTime(2024, 1, 2),
      ]);
    });
  });

  group('LifesumImportJournal', () {
    test('round-trips value-free JSON against the exact manifest', () {
      final journal = LifesumImportJournal.prepare(manifest);

      final encoded = jsonEncode(journal.toJson());
      final restored = LifesumImportJournal.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
        expectedManifest: manifest,
      );

      expect(restored.manifestId, manifest.manifestId);
      expect(restored.phase, LifesumImportJournalPhase.prepared);
      expect(restored.operationProgress, journal.operationProgress);
      expect(encoded, isNot(contains('Example')));
      expect(encoded, isNot(contains('archive')));
      expect(encoded, isNot(contains('payload')));
    });

    test('records a complete apply as explicit durable transitions', () {
      var journal = LifesumImportJournal.prepare(manifest).beginApply();

      for (final operation in manifest.operations) {
        journal = journal.markOperationApplying(operation.operationId);
        expect(
          journal.markOperationApplying(operation.operationId),
          same(journal),
        );
        journal = journal.markOperationApplied(operation.operationId);
        expect(
          journal.markOperationApplied(operation.operationId),
          same(journal),
        );
      }
      journal = journal.completeApply();

      expect(journal.phase, LifesumImportJournalPhase.completed);
      expect(
        journal.countFor(LifesumImportOperationProgress.applied),
        manifest.operationCount,
      );
      expect(journal.failure, isNull);
    });

    test('reconciles an interrupted apply without duplicating a target', () {
      final operationId = manifest.operations.first.operationId;
      final interrupted = LifesumImportJournal.prepare(
        manifest,
      ).beginApply().markOperationApplying(operationId);

      final absent = interrupted.reconcileApplyingOperation(
        operationId,
        LifesumImportTargetProbe.absent,
      );
      final matching = interrupted.reconcileApplyingOperation(
        operationId,
        LifesumImportTargetProbe.matching,
      );
      final conflicting = interrupted.reconcileApplyingOperation(
        operationId,
        LifesumImportTargetProbe.conflicting,
      );

      expect(
        absent.operationProgress[operationId],
        LifesumImportOperationProgress.pending,
      );
      expect(
        matching.operationProgress[operationId],
        LifesumImportOperationProgress.applied,
      );
      expect(conflicting.phase, LifesumImportJournalPhase.rollbackRequired);
      expect(conflicting.failure, LifesumImportJournalFailure.targetConflict);
    });

    test(
      'rolls back applied and ambiguous operations, leaving pending alone',
      () {
        final firstId = manifest.operations[0].operationId;
        final secondId = manifest.operations[1].operationId;
        var journal = LifesumImportJournal.prepare(manifest).beginApply();
        journal = journal
            .markOperationApplying(firstId)
            .markOperationApplied(firstId)
            .markOperationApplying(secondId)
            .requireRollback(LifesumImportJournalFailure.storageFailure)
            .beginRollback();

        journal = journal
            .markOperationRollingBack(secondId)
            .markOperationRolledBack(secondId)
            .markOperationRollingBack(firstId)
            .markOperationRolledBack(firstId)
            .completeRollback();

        expect(journal.phase, LifesumImportJournalPhase.rolledBack);
        expect(journal.failure, LifesumImportJournalFailure.storageFailure);
        expect(journal.countFor(LifesumImportOperationProgress.rolledBack), 2);
        expect(
          journal.countFor(LifesumImportOperationProgress.pending),
          manifest.operationCount - 2,
        );
      },
    );

    test('rejects invalid transitions, snapshots, and manifest reuse', () {
      final journal = LifesumImportJournal.prepare(manifest);
      final otherManifest = LifesumImportManifest.fromPreview(
        preview,
        selection: const LifesumImportSelection(includeEstimatedWater: true),
      );
      final invalidSnapshot = Map<String, dynamic>.of(journal.toJson())
        ..['phase'] = LifesumImportJournalPhase.completed.name;

      expect(
        journal.completeApply,
        _throwsJournalError(LifesumImportJournalError.invalidTransition),
      );
      expect(
        () => journal.beginApply().markOperationApplying('unknown'),
        _throwsJournalError(LifesumImportJournalError.unknownOperation),
      );
      expect(
        () => LifesumImportJournal.fromJson(invalidSnapshot),
        _throwsJournalError(LifesumImportJournalError.invalidSnapshot),
      );
      expect(
        () => LifesumImportJournal.fromJson(
          journal.toJson(),
          expectedManifest: otherManifest,
        ),
        _throwsJournalError(LifesumImportJournalError.manifestMismatch),
      );
    });
  });
}

Matcher _throwsJournalError(LifesumImportJournalError error) => throwsA(
  isA<LifesumImportJournalException>().having(
    (exception) => exception.error,
    'error',
    error,
  ),
);
