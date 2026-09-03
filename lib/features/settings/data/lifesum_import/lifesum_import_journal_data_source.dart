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

  @override
  Future<LifesumImportJournal?> load(LifesumImportManifest manifest) async {
    _requireProfile();
    final encoded = _box.get(manifest.manifestId);
    if (encoded == null) return null;
    return _decode(encoded, expectedManifest: manifest);
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
    return _decode(encoded);
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
    final encoded = jsonEncode(journal.toJson());
    await _box.putAll(<String, String>{
      journal.manifestId: encoded,
      _latestManifestKey: journal.manifestId,
    });
    _requireProfile();
  }

  Future<void> delete(String manifestId) async {
    _requireProfile();
    final keys = <String>[manifestId];
    if (_box.get(_latestManifestKey) == manifestId) {
      keys.add(_latestManifestKey);
    }
    await _box.deleteAll(keys);
    _requireProfile();
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
