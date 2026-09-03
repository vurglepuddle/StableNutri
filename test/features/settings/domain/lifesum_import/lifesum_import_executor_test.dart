import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_executor.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_journal.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_manifest.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_preview.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_tracked_day_plan.dart';

import '../../../../fixture/lifesum_export_fixture.dart';

void main() {
  late Directory temporaryDirectory;
  late LifesumImportManifest primaryManifest;
  late LifesumImportManifest manifest;
  late _MemoryJournalStore journals;
  late _MemoryTargetStore targets;
  late LifesumImportExecutor executor;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'stable_lifesum_executor_',
    );
    final zip = writeSanitizedLifesumZip(temporaryDirectory);
    final selection = const LifesumArchiveReader().readCsvSectionsPath(
      zip.path,
      LifesumExportSection.values.toSet(),
    );
    final preview = LifesumImportPreview.fromSelection(selection);
    primaryManifest = LifesumImportManifest.fromPreview(preview);
    final trackedDays = LifesumTrackedDayPlan.fromManifest(
      primaryManifest,
      goals: LifesumHistoricalGoalSnapshot(
        calorieGoal: 2000,
        carbsGoal: 300,
        fatGoal: 55,
        proteinGoal: 75,
      ),
    );
    manifest = trackedDays.completeManifest(primaryManifest);
    journals = _MemoryJournalStore();
    targets = _MemoryTargetStore();
    executor = LifesumImportExecutor(journals: journals, targets: targets);
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  group('LifesumImportExecutor', () {
    test(
      'applies once in manifest order and returns completed on rerun',
      () async {
        final completed = await executor.execute(manifest);

        expect(completed.phase, LifesumImportJournalPhase.completed);
        expect(targets.applyLog, manifest.operations.map(_operationId));
        expect(targets.targets, hasLength(manifest.operationCount));
        final applyCount = targets.applyLog.length;
        final saveCount = journals.saveCount;

        final repeated = await executor.execute(manifest);

        expect(repeated.phase, LifesumImportJournalPhase.completed);
        expect(targets.applyLog, hasLength(applyCount));
        expect(journals.saveCount, saveCount);
      },
    );

    test(
      'resumes an applying operation by probing instead of duplicating it',
      () async {
        final first = manifest.operations.first;
        journals.current = LifesumImportJournal.prepare(
          manifest,
        ).beginApply().markOperationApplying(first.operationId);
        targets.targets[first.targetKey] = first.operationId;

        final completed = await executor.execute(manifest);

        expect(completed.phase, LifesumImportJournalPhase.completed);
        expect(
          completed.operationProgress[first.operationId],
          LifesumImportOperationProgress.applied,
        );
        expect(targets.applyLog, isNot(contains(first.operationId)));
        expect(targets.applyLog, manifest.operations.skip(1).map(_operationId));
      },
    );

    test(
      'preserves a pre-existing match while rolling back later writes',
      () async {
        final preserved = manifest.operations[0];
        final appliedThenRolledBack = manifest.operations[1];
        final conflict = manifest.operations[2];
        targets.targets[preserved.targetKey] = preserved.operationId;
        targets.targets[conflict.targetKey] = 'different-payload';

        final rolledBack = await executor.execute(manifest);

        expect(rolledBack.phase, LifesumImportJournalPhase.rolledBack);
        expect(
          rolledBack.operationProgress[preserved.operationId],
          LifesumImportOperationProgress.preserved,
        );
        expect(
          rolledBack.operationProgress[appliedThenRolledBack.operationId],
          LifesumImportOperationProgress.rolledBack,
        );
        expect(targets.targets[preserved.targetKey], preserved.operationId);
        expect(targets.targets[conflict.targetKey], 'different-payload');
        expect(targets.rollbackLog, <String>[
          appliedThenRolledBack.operationId,
        ]);
      },
    );

    test('rolls back a write that throws after changing its target', () async {
      final first = manifest.operations[0];
      final interrupted = manifest.operations[1];
      targets.failAfterApply.add(interrupted.operationId);

      final rolledBack = await executor.execute(manifest);

      expect(rolledBack.phase, LifesumImportJournalPhase.rolledBack);
      expect(rolledBack.failure, LifesumImportJournalFailure.storageFailure);
      expect(targets.targets, isEmpty);
      expect(targets.rollbackLog, <String>[
        interrupted.operationId,
        first.operationId,
      ]);
    });

    test('a failed write-ahead save prevents its target mutation', () async {
      journals.failOnSaveCall = 3;

      await expectLater(
        executor.execute(manifest),
        throwsA(
          isA<LifesumImportExecutorException>().having(
            (exception) => exception.error,
            'error',
            LifesumImportExecutorError.journalWriteFailed,
          ),
        ),
      );

      expect(targets.applyLog, isEmpty);
      expect(targets.targets, isEmpty);
      expect(journals.current?.phase, LifesumImportJournalPhase.applying);
      expect(
        journals.current?.countFor(LifesumImportOperationProgress.pending),
        manifest.operationCount,
      );
    });

    test(
      'recovers when the applied-result journal save was interrupted',
      () async {
        final first = manifest.operations.first;
        journals.failOnSaveCall = 4;

        await expectLater(
          executor.execute(manifest),
          throwsA(
            isA<LifesumImportExecutorException>().having(
              (exception) => exception.error,
              'error',
              LifesumImportExecutorError.journalWriteFailed,
            ),
          ),
        );
        expect(targets.applyLog, <String>[first.operationId]);
        expect(
          journals.current?.operationProgress[first.operationId],
          LifesumImportOperationProgress.applying,
        );

        journals.failOnSaveCall = null;
        final completed = await executor.execute(manifest);

        expect(completed.phase, LifesumImportJournalPhase.completed);
        expect(
          targets.applyLog.where((id) => id == first.operationId),
          hasLength(1),
        );
        expect(targets.applyLog, hasLength(manifest.operationCount));
      },
    );

    test('never deletes a changed target while resuming rollback', () async {
      final first = manifest.operations.first;
      journals.current = LifesumImportJournal.prepare(manifest)
          .beginApply()
          .markOperationApplying(first.operationId)
          .markOperationApplied(first.operationId)
          .requireRollback(LifesumImportJournalFailure.storageFailure)
          .beginRollback()
          .markOperationRollingBack(first.operationId);
      targets.targets[first.targetKey] = 'changed-after-apply';

      await expectLater(
        executor.execute(manifest),
        throwsA(
          isA<LifesumImportExecutorException>().having(
            (exception) => exception.error,
            'error',
            LifesumImportExecutorError.rollbackConflict,
          ),
        ),
      );

      expect(targets.targets[first.targetKey], 'changed-after-apply');
      expect(targets.rollbackLog, isEmpty);
      expect(
        journals.current?.operationProgress[first.operationId],
        LifesumImportOperationProgress.rollingBack,
      );
    });

    test(
      'rejects an incomplete primary manifest before loading a journal',
      () async {
        await expectLater(
          executor.execute(primaryManifest),
          throwsA(
            isA<LifesumImportExecutorException>().having(
              (exception) => exception.error,
              'error',
              LifesumImportExecutorError.incompleteManifest,
            ),
          ),
        );
        expect(journals.loadCount, 0);
        expect(journals.saveCount, 0);
        expect(targets.targets, isEmpty);
      },
    );
  });
}

String _operationId(LifesumImportOperation operation) => operation.operationId;

class _MemoryJournalStore implements LifesumImportJournalStore {
  LifesumImportJournal? current;
  int loadCount = 0;
  int saveCount = 0;
  int? failOnSaveCall;

  @override
  Future<LifesumImportJournal?> load(LifesumImportManifest manifest) async {
    loadCount++;
    current?.requireManifest(manifest);
    return current;
  }

  @override
  Future<void> save(LifesumImportJournal journal) async {
    saveCount++;
    if (saveCount == failOnSaveCall) throw StateError('synthetic save failure');
    current = journal;
  }
}

class _MemoryTargetStore implements LifesumImportTargetStore {
  final Map<String, String> targets = <String, String>{};
  final List<String> applyLog = <String>[];
  final List<String> rollbackLog = <String>[];
  final Set<String> failAfterApply = <String>{};

  @override
  Future<LifesumImportTargetProbe> probe(
    LifesumImportOperation operation,
  ) async {
    final storedOperationId = targets[operation.targetKey];
    if (storedOperationId == null) return LifesumImportTargetProbe.absent;
    return storedOperationId == operation.operationId
        ? LifesumImportTargetProbe.matching
        : LifesumImportTargetProbe.conflicting;
  }

  @override
  Future<void> apply(LifesumImportOperation operation) async {
    applyLog.add(operation.operationId);
    targets[operation.targetKey] = operation.operationId;
    if (failAfterApply.contains(operation.operationId)) {
      throw StateError('synthetic target failure');
    }
  }

  @override
  Future<void> rollback(LifesumImportOperation operation) async {
    rollbackLog.add(operation.operationId);
    targets.remove(operation.targetKey);
  }
}
