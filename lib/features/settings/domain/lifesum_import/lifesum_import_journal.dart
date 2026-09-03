import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_manifest.dart';

enum LifesumImportJournalPhase {
  prepared,
  applying,
  rollbackRequired,
  rollingBack,
  completed,
  rolledBack,
}

enum LifesumImportOperationProgress {
  pending,
  applying,
  applied,
  rollingBack,
  rolledBack,
}

enum LifesumImportJournalFailure { targetConflict, storageFailure }

enum LifesumImportTargetProbe { absent, matching, conflicting }

enum LifesumImportJournalError {
  invalidSnapshot,
  manifestMismatch,
  invalidTransition,
  unknownOperation,
}

class LifesumImportJournalException implements Exception {
  const LifesumImportJournalException(this.error);

  final LifesumImportJournalError error;

  @override
  String toString() => 'Lifesum import journal error: $error';
}

/// Value-free, serializable progress for a single confirmed manifest.
///
/// The journal persists only deterministic operation IDs and state. Candidate
/// payloads, source strings, archive paths, and health values never enter it.
class LifesumImportJournal {
  LifesumImportJournal._({
    required this.manifestId,
    required this.phase,
    required Map<String, LifesumImportOperationProgress> operationProgress,
    required this.failure,
  }) : operationProgress =
           Map<String, LifesumImportOperationProgress>.unmodifiable(
             operationProgress,
           ) {
    _validateCoherence();
  }

  factory LifesumImportJournal.prepare(LifesumImportManifest manifest) =>
      LifesumImportJournal._(
        manifestId: manifest.manifestId,
        phase: LifesumImportJournalPhase.prepared,
        operationProgress: <String, LifesumImportOperationProgress>{
          for (final operation in manifest.operations)
            operation.operationId: LifesumImportOperationProgress.pending,
        },
        failure: null,
      );

  factory LifesumImportJournal.fromJson(
    Map<String, dynamic> json, {
    LifesumImportManifest? expectedManifest,
  }) {
    try {
      if (json['schemaVersion'] != schemaVersion) {
        throw const LifesumImportJournalException(
          LifesumImportJournalError.invalidSnapshot,
        );
      }
      final manifestId = json['manifestId'];
      final rawPhase = json['phase'];
      final rawOperations = json['operations'];
      final rawFailure = json['failure'];
      if (manifestId is! String ||
          manifestId.isEmpty ||
          rawPhase is! String ||
          rawOperations is! List ||
          (rawFailure != null && rawFailure is! String)) {
        throw const LifesumImportJournalException(
          LifesumImportJournalError.invalidSnapshot,
        );
      }

      final phase = _enumByName(LifesumImportJournalPhase.values, rawPhase);
      final failure = rawFailure == null
          ? null
          : _enumByName(LifesumImportJournalFailure.values, rawFailure);
      final operationProgress = <String, LifesumImportOperationProgress>{};
      for (final rawOperation in rawOperations) {
        if (rawOperation is! Map) {
          throw const LifesumImportJournalException(
            LifesumImportJournalError.invalidSnapshot,
          );
        }
        final id = rawOperation['id'];
        final rawProgress = rawOperation['progress'];
        if (id is! String ||
            id.isEmpty ||
            rawProgress is! String ||
            operationProgress.containsKey(id)) {
          throw const LifesumImportJournalException(
            LifesumImportJournalError.invalidSnapshot,
          );
        }
        operationProgress[id] = _enumByName(
          LifesumImportOperationProgress.values,
          rawProgress,
        );
      }

      final journal = LifesumImportJournal._(
        manifestId: manifestId,
        phase: phase,
        operationProgress: operationProgress,
        failure: failure,
      );
      if (expectedManifest != null) {
        journal.requireManifest(expectedManifest);
      }
      return journal;
    } on LifesumImportJournalException {
      rethrow;
    } on Object {
      throw const LifesumImportJournalException(
        LifesumImportJournalError.invalidSnapshot,
      );
    }
  }

  static const schemaVersion = 1;

  final String manifestId;
  final LifesumImportJournalPhase phase;
  final Map<String, LifesumImportOperationProgress> operationProgress;
  final LifesumImportJournalFailure? failure;

  int get operationCount => operationProgress.length;
  int countFor(LifesumImportOperationProgress progress) =>
      operationProgress.values.where((current) => current == progress).length;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'manifestId': manifestId,
    'phase': phase.name,
    'failure': failure?.name,
    'operations': <Map<String, String>>[
      for (final entry in operationProgress.entries)
        <String, String>{'id': entry.key, 'progress': entry.value.name},
    ],
  };

  void requireManifest(LifesumImportManifest manifest) {
    final operationIds = manifest.operations
        .map((operation) => operation.operationId)
        .toList(growable: false);
    if (manifest.manifestId != manifestId ||
        !_orderedEquals(operationProgress.keys, operationIds)) {
      throw const LifesumImportJournalException(
        LifesumImportJournalError.manifestMismatch,
      );
    }
  }

  LifesumImportJournal beginApply() {
    _requirePhase(LifesumImportJournalPhase.prepared);
    return _copyWith(phase: LifesumImportJournalPhase.applying);
  }

  LifesumImportJournal markOperationApplying(String operationId) {
    _requirePhase(LifesumImportJournalPhase.applying);
    final progress = _progressFor(operationId);
    if (progress == LifesumImportOperationProgress.applying) return this;
    _requireProgress(progress, LifesumImportOperationProgress.pending);
    return _withProgress(operationId, LifesumImportOperationProgress.applying);
  }

  LifesumImportJournal markOperationApplied(String operationId) {
    _requirePhase(LifesumImportJournalPhase.applying);
    final progress = _progressFor(operationId);
    if (progress == LifesumImportOperationProgress.applied) return this;
    _requireProgress(progress, LifesumImportOperationProgress.applying);
    return _withProgress(operationId, LifesumImportOperationProgress.applied);
  }

  /// Resolves a crash after "applying" was durably journaled but before the
  /// result was. Matching data is accepted, absence is retried, and a
  /// different value at the deterministic target forces rollback.
  LifesumImportJournal reconcileApplyingOperation(
    String operationId,
    LifesumImportTargetProbe probe,
  ) {
    _requirePhase(LifesumImportJournalPhase.applying);
    final progress = _progressFor(operationId);
    _requireProgress(progress, LifesumImportOperationProgress.applying);
    return switch (probe) {
      LifesumImportTargetProbe.absent => _withProgress(
        operationId,
        LifesumImportOperationProgress.pending,
      ),
      LifesumImportTargetProbe.matching => _withProgress(
        operationId,
        LifesumImportOperationProgress.applied,
      ),
      LifesumImportTargetProbe.conflicting => _copyWith(
        phase: LifesumImportJournalPhase.rollbackRequired,
        failure: LifesumImportJournalFailure.targetConflict,
      ),
    };
  }

  LifesumImportJournal completeApply() {
    _requirePhase(LifesumImportJournalPhase.applying);
    if (operationProgress.values.any(
      (progress) => progress != LifesumImportOperationProgress.applied,
    )) {
      throw const LifesumImportJournalException(
        LifesumImportJournalError.invalidTransition,
      );
    }
    return _copyWith(phase: LifesumImportJournalPhase.completed);
  }

  LifesumImportJournal requireRollback(LifesumImportJournalFailure reason) {
    if (phase == LifesumImportJournalPhase.rollbackRequired) {
      if (failure == reason) return this;
      throw const LifesumImportJournalException(
        LifesumImportJournalError.invalidTransition,
      );
    }
    _requirePhase(LifesumImportJournalPhase.applying);
    return _copyWith(
      phase: LifesumImportJournalPhase.rollbackRequired,
      failure: reason,
    );
  }

  LifesumImportJournal beginRollback() {
    if (phase == LifesumImportJournalPhase.rollingBack) return this;
    _requirePhase(LifesumImportJournalPhase.rollbackRequired);
    return _copyWith(phase: LifesumImportJournalPhase.rollingBack);
  }

  LifesumImportJournal markOperationRollingBack(String operationId) {
    _requirePhase(LifesumImportJournalPhase.rollingBack);
    final progress = _progressFor(operationId);
    if (progress == LifesumImportOperationProgress.rollingBack ||
        progress == LifesumImportOperationProgress.rolledBack) {
      return this;
    }
    if (progress != LifesumImportOperationProgress.applied &&
        progress != LifesumImportOperationProgress.applying) {
      throw const LifesumImportJournalException(
        LifesumImportJournalError.invalidTransition,
      );
    }
    return _withProgress(
      operationId,
      LifesumImportOperationProgress.rollingBack,
    );
  }

  LifesumImportJournal markOperationRolledBack(String operationId) {
    _requirePhase(LifesumImportJournalPhase.rollingBack);
    final progress = _progressFor(operationId);
    if (progress == LifesumImportOperationProgress.rolledBack) return this;
    _requireProgress(progress, LifesumImportOperationProgress.rollingBack);
    return _withProgress(
      operationId,
      LifesumImportOperationProgress.rolledBack,
    );
  }

  LifesumImportJournal completeRollback() {
    _requirePhase(LifesumImportJournalPhase.rollingBack);
    if (operationProgress.values.any(
      (progress) =>
          progress != LifesumImportOperationProgress.pending &&
          progress != LifesumImportOperationProgress.rolledBack,
    )) {
      throw const LifesumImportJournalException(
        LifesumImportJournalError.invalidTransition,
      );
    }
    return _copyWith(phase: LifesumImportJournalPhase.rolledBack);
  }

  LifesumImportOperationProgress _progressFor(String operationId) {
    final progress = operationProgress[operationId];
    if (progress == null) {
      throw const LifesumImportJournalException(
        LifesumImportJournalError.unknownOperation,
      );
    }
    return progress;
  }

  void _requirePhase(LifesumImportJournalPhase expected) {
    if (phase != expected) {
      throw const LifesumImportJournalException(
        LifesumImportJournalError.invalidTransition,
      );
    }
  }

  static void _requireProgress(
    LifesumImportOperationProgress actual,
    LifesumImportOperationProgress expected,
  ) {
    if (actual != expected) {
      throw const LifesumImportJournalException(
        LifesumImportJournalError.invalidTransition,
      );
    }
  }

  LifesumImportJournal _withProgress(
    String operationId,
    LifesumImportOperationProgress progress,
  ) {
    final next = Map<String, LifesumImportOperationProgress>.of(
      operationProgress,
    )..[operationId] = progress;
    return _copyWith(operationProgress: next);
  }

  LifesumImportJournal _copyWith({
    LifesumImportJournalPhase? phase,
    Map<String, LifesumImportOperationProgress>? operationProgress,
    LifesumImportJournalFailure? failure,
  }) => LifesumImportJournal._(
    manifestId: manifestId,
    phase: phase ?? this.phase,
    operationProgress: operationProgress ?? this.operationProgress,
    failure: failure ?? this.failure,
  );

  void _validateCoherence() {
    final values = operationProgress.values;
    final valid = switch (phase) {
      LifesumImportJournalPhase.prepared =>
        failure == null &&
            values.every(
              (progress) => progress == LifesumImportOperationProgress.pending,
            ),
      LifesumImportJournalPhase.applying =>
        failure == null &&
            values.every(
              (progress) =>
                  progress == LifesumImportOperationProgress.pending ||
                  progress == LifesumImportOperationProgress.applying ||
                  progress == LifesumImportOperationProgress.applied,
            ),
      LifesumImportJournalPhase.rollbackRequired =>
        failure != null &&
            values.every(
              (progress) =>
                  progress == LifesumImportOperationProgress.pending ||
                  progress == LifesumImportOperationProgress.applying ||
                  progress == LifesumImportOperationProgress.applied,
            ),
      LifesumImportJournalPhase.rollingBack =>
        failure != null &&
            values.every(
              (progress) =>
                  progress == LifesumImportOperationProgress.pending ||
                  progress == LifesumImportOperationProgress.applying ||
                  progress == LifesumImportOperationProgress.applied ||
                  progress == LifesumImportOperationProgress.rollingBack ||
                  progress == LifesumImportOperationProgress.rolledBack,
            ),
      LifesumImportJournalPhase.completed =>
        failure == null &&
            values.every(
              (progress) => progress == LifesumImportOperationProgress.applied,
            ),
      LifesumImportJournalPhase.rolledBack =>
        failure != null &&
            values.every(
              (progress) =>
                  progress == LifesumImportOperationProgress.pending ||
                  progress == LifesumImportOperationProgress.rolledBack,
            ),
    };
    if (!valid) {
      throw const LifesumImportJournalException(
        LifesumImportJournalError.invalidSnapshot,
      );
    }
  }
}

T _enumByName<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw const LifesumImportJournalException(
    LifesumImportJournalError.invalidSnapshot,
  );
}

bool _orderedEquals(Iterable<String> left, List<String> right) {
  final leftValues = left.toList(growable: false);
  if (leftValues.length != right.length) return false;
  for (var index = 0; index < leftValues.length; index++) {
    if (leftValues[index] != right[index]) return false;
  }
  return true;
}
