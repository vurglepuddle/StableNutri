import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_journal.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_manifest.dart';

abstract interface class LifesumImportJournalStore {
  Future<LifesumImportJournal?> load(LifesumImportManifest manifest);
  Future<void> save(LifesumImportJournal journal);
}

/// The future Hive adapter implements this contract with conditional writes.
/// Tests use an in-memory implementation; no production domain store is wired
/// while the failure semantics are being established.
abstract interface class LifesumImportTargetStore {
  Future<LifesumImportTargetProbe> probe(LifesumImportOperation operation);
  Future<void> apply(LifesumImportOperation operation);
  Future<void> rollback(LifesumImportOperation operation);
}

enum LifesumImportExecutorError {
  incompleteManifest,
  journalReadFailed,
  journalWriteFailed,
  targetReadFailed,
  targetWriteFailed,
  rollbackConflict,
}

class LifesumImportExecutorException implements Exception {
  const LifesumImportExecutorException(this.error, {this.journal});

  final LifesumImportExecutorError error;
  final LifesumImportJournal? journal;

  @override
  String toString() => 'Lifesum import executor error: $error';
}

/// Executes one completed manifest with write-ahead journaling.
///
/// Journal saves always precede target mutation. A crash with an operation in
/// `applying` is reconciled by probing its deterministic target. Rollback runs
/// in reverse manifest order and never removes a target whose payload differs.
class LifesumImportExecutor {
  const LifesumImportExecutor({
    required LifesumImportJournalStore journals,
    required LifesumImportTargetStore targets,
  }) : _journals = journals,
       _targets = targets;

  final LifesumImportJournalStore _journals;
  final LifesumImportTargetStore _targets;

  Future<LifesumImportJournal> execute(LifesumImportManifest manifest) async {
    if (!manifest.isExecutable) {
      throw const LifesumImportExecutorException(
        LifesumImportExecutorError.incompleteManifest,
      );
    }

    LifesumImportJournal? journal;
    try {
      journal = await _journals.load(manifest);
    } on Object {
      throw const LifesumImportExecutorException(
        LifesumImportExecutorError.journalReadFailed,
      );
    }
    if (journal == null) {
      journal = LifesumImportJournal.prepare(manifest);
      journal = await _save(journal);
    } else {
      journal.requireManifest(manifest);
    }

    switch (journal.phase) {
      case LifesumImportJournalPhase.completed:
      case LifesumImportJournalPhase.rolledBack:
        return journal;
      case LifesumImportJournalPhase.prepared:
        journal = await _save(journal.beginApply());
        return _apply(manifest, journal);
      case LifesumImportJournalPhase.applying:
        return _apply(manifest, journal);
      case LifesumImportJournalPhase.rollbackRequired:
      case LifesumImportJournalPhase.rollingBack:
        return _rollback(manifest, journal);
    }
  }

  Future<LifesumImportJournal> _apply(
    LifesumImportManifest manifest,
    LifesumImportJournal journal,
  ) async {
    var current = journal;

    for (final operation in manifest.operations) {
      if (current.operationProgress[operation.operationId] !=
          LifesumImportOperationProgress.applying) {
        continue;
      }
      final (probe, reconciledJournal) = await _probeForApply(
        current,
        operation,
      );
      current = reconciledJournal;
      if (probe == null) {
        return _rollback(manifest, current);
      }
      current = await _save(
        current.reconcileApplyingOperation(operation.operationId, probe),
      );
      if (current.phase == LifesumImportJournalPhase.rollbackRequired) {
        return _rollback(manifest, current);
      }
    }

    for (final operation in manifest.operations) {
      if (current.operationProgress[operation.operationId] !=
          LifesumImportOperationProgress.pending) {
        continue;
      }
      final (before, probedJournal) = await _probeForApply(current, operation);
      current = probedJournal;
      if (before == null) return _rollback(manifest, current);
      switch (before) {
        case LifesumImportTargetProbe.matching:
          current = await _save(
            current.markOperationPreserved(operation.operationId),
          );
          continue;
        case LifesumImportTargetProbe.conflicting:
          current = await _save(
            current.requireRollback(LifesumImportJournalFailure.targetConflict),
          );
          return _rollback(manifest, current);
        case LifesumImportTargetProbe.absent:
          break;
      }

      current = await _save(
        current.markOperationApplying(operation.operationId),
      );
      try {
        await _targets.apply(operation);
      } on Object {
        current = await _save(
          current.requireRollback(LifesumImportJournalFailure.storageFailure),
        );
        return _rollback(manifest, current);
      }

      final (after, verifiedJournal) = await _probeForApply(current, operation);
      current = verifiedJournal;
      if (after == null) return _rollback(manifest, current);
      if (after != LifesumImportTargetProbe.matching) {
        current = await _save(
          current.requireRollback(
            after == LifesumImportTargetProbe.conflicting
                ? LifesumImportJournalFailure.targetConflict
                : LifesumImportJournalFailure.storageFailure,
          ),
        );
        return _rollback(manifest, current);
      }
      current = await _save(
        current.markOperationApplied(operation.operationId),
      );
    }

    return _save(current.completeApply());
  }

  Future<(LifesumImportTargetProbe?, LifesumImportJournal)> _probeForApply(
    LifesumImportJournal journal,
    LifesumImportOperation operation,
  ) async {
    try {
      return (await _targets.probe(operation), journal);
    } on Object {
      final rollbackJournal = await _save(
        journal.requireRollback(LifesumImportJournalFailure.storageFailure),
      );
      return (null, rollbackJournal);
    }
  }

  Future<LifesumImportJournal> _rollback(
    LifesumImportManifest manifest,
    LifesumImportJournal journal,
  ) async {
    var current = journal.phase == LifesumImportJournalPhase.rollbackRequired
        ? await _save(journal.beginRollback())
        : journal;
    for (final operation in manifest.operations.reversed) {
      final progress = current.operationProgress[operation.operationId];
      if (progress == LifesumImportOperationProgress.pending ||
          progress == LifesumImportOperationProgress.preserved ||
          progress == LifesumImportOperationProgress.rolledBack) {
        continue;
      }
      if (progress == LifesumImportOperationProgress.applied ||
          progress == LifesumImportOperationProgress.applying) {
        current = await _save(
          current.markOperationRollingBack(operation.operationId),
        );
      }

      final before = await _probeForRollback(current, operation);
      if (before == LifesumImportTargetProbe.conflicting) {
        throw LifesumImportExecutorException(
          LifesumImportExecutorError.rollbackConflict,
          journal: current,
        );
      }
      if (before == LifesumImportTargetProbe.matching) {
        try {
          await _targets.rollback(operation);
        } on Object {
          throw LifesumImportExecutorException(
            LifesumImportExecutorError.targetWriteFailed,
            journal: current,
          );
        }
        final after = await _probeForRollback(current, operation);
        if (after != LifesumImportTargetProbe.absent) {
          throw LifesumImportExecutorException(
            LifesumImportExecutorError.rollbackConflict,
            journal: current,
          );
        }
      }
      current = await _save(
        current.markOperationRolledBack(operation.operationId),
      );
    }
    return _save(current.completeRollback());
  }

  Future<LifesumImportTargetProbe> _probeForRollback(
    LifesumImportJournal journal,
    LifesumImportOperation operation,
  ) async {
    try {
      return await _targets.probe(operation);
    } on Object {
      throw LifesumImportExecutorException(
        LifesumImportExecutorError.targetReadFailed,
        journal: journal,
      );
    }
  }

  Future<LifesumImportJournal> _save(LifesumImportJournal journal) async {
    try {
      await _journals.save(journal);
      return journal;
    } on Object {
      throw LifesumImportExecutorException(
        LifesumImportExecutorError.journalWriteFailed,
        journal: journal,
      );
    }
  }
}
