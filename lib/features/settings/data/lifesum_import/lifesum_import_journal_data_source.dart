import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_executor.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_journal.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_manifest.dart';

enum LifesumImportJournalStoreFailure { activeImportExists, profileChanged }

class LifesumImportJournalStoreException implements Exception {
  const LifesumImportJournalStoreException(this.failure);

  final LifesumImportJournalStoreFailure failure;

  @override
  String toString() => 'Lifesum journal store error: $failure';
}

/// Persists only value-free journal JSON in the active profile's encrypted
/// Hive box. Candidate payloads remain in the in-memory manifest.
class LifesumImportJournalDataSource implements LifesumImportJournalStore {
  LifesumImportJournalDataSource(HiveDBProvider database)
    : _database = database,
      _profileId = database.activeProfileId,
      _profileGeneration = database.activeProfileGeneration,
      _box = database.lifesumImportJournalBox;

  static const _latestManifestKey = '_latestManifest';

  final HiveDBProvider _database;
  final String _profileId;
  final int _profileGeneration;
  final Box<String> _box;
  LifesumImportJournal? _lastSaved;
  int _nextSequence = 0;

  String _stepPrefix(String manifestId) => '$manifestId:step:';

  @override
  Future<LifesumImportJournal?> load(LifesumImportManifest manifest) async {
    _requireProfile();
    final encoded = _box.get(manifest.manifestId);
    if (encoded == null) return null;
    final journal = _restore(manifest.manifestId, encoded);
    journal.requireManifest(manifest);
    return journal;
  }

  Future<LifesumImportJournal?> loadLatest() async {
    _requireProfile();
    final manifestId = _box.get(_latestManifestKey);
    if (manifestId == null) return null;
    final encoded = _box.get(manifestId);
    if (encoded == null) {
      throw const LifesumImportJournalException(
        LifesumImportJournalError.invalidSnapshot,
      );
    }
    return _restore(manifestId, encoded);
  }

  @override
  Future<void> save(LifesumImportJournal journal) async {
    _requireProfile();
    final latestManifestId = _box.get(_latestManifestKey);
    if (latestManifestId != null && latestManifestId != journal.manifestId) {
      final latest = await loadLatest();
      if (latest != null && !latest.isTerminal) {
        throw const LifesumImportJournalStoreException(
          LifesumImportJournalStoreFailure.activeImportExists,
        );
      }
    }
    final encoded = _box.get(journal.manifestId);
    if (encoded == null) {
      await _box.putAll(<String, String>{
        journal.manifestId: jsonEncode(journal.toJson()),
        _latestManifestKey: journal.manifestId,
      });
      _nextSequence = 0;
    } else {
      if (_lastSaved?.manifestId != journal.manifestId) {
        _restore(journal.manifestId, encoded);
      }
      if (identical(_lastSaved?.revision, journal.revision)) return;
      final incremental = identical(
        _lastSaved?.revision,
        journal.previousRevision,
      );
      final changedId = journal.changedOperationId;
      final step = incremental
          ? <String, dynamic>{
              'phase': journal.phase.name,
              'failure': journal.failure?.name,
              'id': ?changedId,
              if (changedId != null)
                'progress': journal.operationProgress[changedId]!.name,
            }
          : <String, dynamic>{'snapshot': journal.toJson()};
      // One bounded Hive record per transition. Awaiting this write preserves
      // the executor's write-ahead boundary, including ambiguous crash recovery.
      await _box.put(
        '${_stepPrefix(journal.manifestId)}$_nextSequence',
        jsonEncode(step),
      );
      _nextSequence++;
      if (latestManifestId != journal.manifestId) {
        await _box.put(_latestManifestKey, journal.manifestId);
      }
    }
    _lastSaved = journal;
    _requireProfile();
  }

  Future<void> delete(String manifestId) async {
    _requireProfile();
    final keys = <dynamic>[
      manifestId,
      ..._box.keys.where(
        (key) => key is String && key.startsWith(_stepPrefix(manifestId)),
      ),
    ];
    if (_box.get(_latestManifestKey) == manifestId) {
      keys.add(_latestManifestKey);
    }
    await _box.deleteAll(keys);
    if (_lastSaved?.manifestId == manifestId) _lastSaved = null;
    _requireProfile();
  }

  LifesumImportJournal _restore(String manifestId, String encoded) {
    try {
      var snapshot = _decode(encoded).toJson();
      var operations = <String, String>{
        for (final operation in snapshot['operations'] as List)
          operation['id'] as String: operation['progress'] as String,
      };
      final prefix = _stepPrefix(manifestId);
      final count = _box.keys
          .where((key) => key is String && key.startsWith(prefix))
          .length;
      for (var sequence = 0; sequence < count; sequence++) {
        final step =
            jsonDecode(_box.get('$prefix$sequence')!) as Map<String, dynamic>;
        if (step.containsKey('snapshot')) {
          snapshot = LifesumImportJournal.fromJson(
            step['snapshot'] as Map<String, dynamic>,
          ).toJson();
          operations = <String, String>{
            for (final operation in snapshot['operations'] as List)
              operation['id'] as String: operation['progress'] as String,
          };
        } else {
          snapshot['phase'] = step['phase'];
          snapshot['failure'] = step['failure'];
          if (step.containsKey('id')) {
            final id = step['id'] as String;
            if (!operations.containsKey(id)) throw const FormatException();
            operations[id] = step['progress'] as String;
          }
        }
      }
      snapshot['operations'] = <Map<String, String>>[
        for (final operation in operations.entries)
          <String, String>{'id': operation.key, 'progress': operation.value},
      ];
      final journal = LifesumImportJournal.fromJson(snapshot);
      if (journal.manifestId != manifestId) throw const FormatException();
      _lastSaved = journal;
      _nextSequence = count;
      return journal;
    } on Object {
      throw const LifesumImportJournalException(
        LifesumImportJournalError.invalidSnapshot,
      );
    }
  }

  void _requireProfile() {
    if (_database.activeProfileId != _profileId ||
        _database.activeProfileGeneration != _profileGeneration ||
        !_box.isOpen) {
      throw const LifesumImportJournalStoreException(
        LifesumImportJournalStoreFailure.profileChanged,
      );
    }
  }

  static LifesumImportJournal _decode(
    String encoded, {
    LifesumImportManifest? expectedManifest,
  }) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) {
        throw const LifesumImportJournalException(
          LifesumImportJournalError.invalidSnapshot,
        );
      }
      return LifesumImportJournal.fromJson(
        decoded,
        expectedManifest: expectedManifest,
      );
    } on LifesumImportJournalException {
      rethrow;
    } on Object {
      throw const LifesumImportJournalException(
        LifesumImportJournalError.invalidSnapshot,
      );
    }
  }
}
