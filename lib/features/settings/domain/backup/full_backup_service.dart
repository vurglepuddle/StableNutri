import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/data/dbo/profile_dbo.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';
import 'package:opennutritracker/features/cycle/domain/cycle_data.dart';
import 'package:opennutritracker/features/settings/domain/backup/backup_codec.dart';

class BackupStore {
  final String base;
  final String suffix;
  final Map<dynamic, dynamic> rows;
  const BackupStore(this.base, this.suffix, this.rows);
}

class FullBackup {
  final String activeProfile;
  final List<BackupStore> stores;
  final Map<String, List<int>> images;
  final int profileCount;
  final int missingPhotoCount;
  const FullBackup(
    this.activeProfile,
    this.stores,
    this.images,
    this.profileCount, {
    this.missingPhotoCount = 0,
  });
}

/// Full snapshots restore to new encrypted boxes and a separate image root.
/// Only an atomic pointer rename makes the dataset visible on next startup.
/// Existing records and images are never overwritten by staging or failure.
class FullBackupService {
  final HiveDBProvider db;
  FullBackupService(this.db);
  static const globals = [
    HiveDBProvider.profileBoxName,
    HiveDBProvider.appConfigBoxName,
    HiveDBProvider.customMealBoxName,
    HiveDBProvider.recipeBoxName,
    HiveDBProvider.customActivityTemplateBoxName,
  ];
  static const manifestName = 'stable_backup.json';
  static const maxBytes = 512 * 1024 * 1024;

  Future<Uint8List> export() async {
    if (db.restorePending) throw StateError('Restart required');
    final generation = db.activeProfileGeneration;
    final profiles = db.profileBox.values.toList();
    final opened = <({String base, String suffix, Box<dynamic> box})>[];
    for (final base in globals) {
      opened.add((base: base, suffix: '', box: await db.openDataBox(base)));
    }
    for (final profile in profiles) {
      for (final base in HiveDBProvider.perProfileBoxNames) {
        opened.add((
          base: base,
          suffix: profile.boxSuffix,
          box: await db.openDataBox(base, suffix: profile.boxSuffix),
        ));
      }
    }
    if (generation != db.activeProfileGeneration ||
        profiles.length != db.profileBox.length) {
      throw StateError('Profiles changed');
    }
    // No await during the snapshot: all boxes are read in one event-loop turn.
    final snapshot = <String, dynamic>{
      'format': 'stable-full-backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'activeProfile': db.activeProfileId,
      'stores': [
        for (final item in opened)
          {
            'base': item.base,
            'suffix': item.suffix,
            'rows': [
              for (final key in item.box.keys)
                {
                  'key': key,
                  'value': BackupCodec.encode(item.base, item.box.get(key)),
                },
            ],
          },
      ],
    };
    final payload = jsonEncode(snapshot);
    final archive = Archive();
    final images = <String>{};
    void collect(Object? value) {
      if (value is String && UserImageStorage.isUserImagePath(value)) {
        images.add(value);
      }
      if (value is List) {
        for (final v in value) {
          collect(v);
        }
      }
      if (value is Map) {
        for (final v in value.values) {
          collect(v);
        }
      }
    }

    collect(jsonDecode(payload));
    final included = <String>[];
    for (final path in images) {
      if (!_safeImage(path)) throw const FormatException('Invalid image path');
      final file = File(await UserImageStorage.absolutePath(path));
      // Already-missing photos cannot be recovered, but the record is preserved.
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
      included.add(path);
    }
    final manifest = utf8.encode(
      jsonEncode({
        ...jsonDecode(payload) as Map,
        'images': included,
        'missingImages': images.difference(included.toSet()).toList(),
      }),
    );
    archive.addFile(ArchiveFile(manifestName, manifest.length, manifest));
    if (generation != db.activeProfileGeneration) {
      throw StateError('Profile changed');
    }
    if (archive.files.fold<int>(0, (sum, f) => sum + f.size) > maxBytes) {
      throw const FormatException('Backup too large');
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static bool _safeImage(String name) =>
      RegExp(
        r'^(meal_images|recipe_images|profile_images)/[a-zA-Z0-9_.-]+$',
      ).hasMatch(name) &&
      !name.contains('..');

  /// Validate every store, row and attachment before any target write.
  FullBackup inspect(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Backup too large');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.files.fold<int>(0, (sum, f) => sum + f.size) > maxBytes) {
      throw const FormatException('Expanded backup too large');
    }
    final entries = <String, ArchiveFile>{};
    for (final f in archive.files) {
      if (!f.isFile ||
          entries.containsKey(f.name) ||
          (f.name != manifestName && !_safeImage(f.name))) {
        throw const FormatException('Invalid or duplicate archive path');
      }
      entries[f.name] = f;
    }
    final manifest = entries.remove(manifestName);
    if (manifest == null) {
      throw const FormatException('Not a full Stable backup');
    }
    final j =
        jsonDecode(utf8.decode(manifest.content as List<int>))
            as Map<String, dynamic>;
    if (j['format'] != 'stable-full-backup' || j['version'] != 1) {
      throw const FormatException('Unsupported backup version');
    }
    final stores = <BackupStore>[];
    final seen = <String>{};
    for (final raw in j['stores'] as List) {
      final base = raw['base'] as String;
      final suffix = raw['suffix'] as String;
      if ((!globals.contains(base) &&
              !HiveDBProvider.perProfileBoxNames.contains(base)) ||
          !RegExp(r'^[a-zA-Z0-9_-]*$').hasMatch(suffix) ||
          (globals.contains(base) && suffix.isNotEmpty) ||
          !seen.add('$base/$suffix')) {
        throw const FormatException('Invalid backup store');
      }
      final rows = <dynamic, dynamic>{};
      for (final row in raw['rows'] as List) {
        final key = row['key'];
        if ((key is! String && key is! int) ||
            rows.containsKey(key) ||
            (key is int && (key < 0 || key > 0xffffffff))) {
          throw const FormatException('Invalid row key');
        }
        final value = BackupCodec.decode(base, row['value']);
        if (base == HiveDBProvider.cycleBoxName) {
          CycleData.decode(value as String);
        }
        rows[key] = value;
      }
      stores.add(BackupStore(base, suffix, rows));
    }
    final profiles = stores
        .singleWhere((s) => s.base == HiveDBProvider.profileBoxName)
        .rows;
    final suffixes = <String>{};
    final expected = <String>{for (final g in globals) '$g/'};
    for (final entry in profiles.entries) {
      final p = entry.value as ProfileDBO;
      if (p.id != entry.key || !suffixes.add(p.boxSuffix)) {
        throw const FormatException('Invalid profiles');
      }
      for (final base in HiveDBProvider.perProfileBoxNames) {
        expected.add('$base/${p.boxSuffix}');
      }
    }
    if (profiles.isEmpty ||
        !profiles.containsKey(j['activeProfile']) ||
        seen.length != expected.length ||
        !seen.containsAll(expected)) {
      throw const FormatException('Incomplete backup');
    }
    final names = (j['images'] as List).cast<String>();
    if (names.toSet().length != names.length ||
        names.length != entries.length ||
        !names.every(entries.containsKey)) {
      throw const FormatException('Missing attachments');
    }
    return FullBackup(
      j['activeProfile'] as String,
      stores,
      {for (final name in names) name: entries[name]!.content as List<int>},
      profiles.length,
      missingPhotoCount: (j['missingImages'] as List).length,
    );
  }

  Future<void> restore(FullBackup backup) async {
    if (db.restorePending) throw StateError('Restart required');
    final namespace =
        'restore_${IdGenerator.getUniqueID().replaceAll('-', '_')}';
    final opened = <Box<dynamic>>[];
    try {
      for (final store in backup.stores) {
        final box = await db.openDataBox(
          store.base,
          suffix: store.suffix,
          namespace: namespace,
        );
        opened.add(box);
        if (box.isNotEmpty) throw StateError('Restore namespace collision');
        final rows = <dynamic, dynamic>{};
        for (final entry in store.rows.entries) {
          // Fresh instances: do not attach the inspected DBOs to a staged box.
          var value = BackupCodec.decode(
            store.base,
            jsonDecode(jsonEncode(BackupCodec.encode(store.base, entry.value))),
          );
          if (value is ConfigDBO) value.notificationsEnabled = false;
          if (store.base == HiveDBProvider.dailyStepsBoxName &&
              entry.key == '_autoImport') {
            value = 'false';
          }
          if (store.base == HiveDBProvider.cycleBoxName) {
            value = CycleData.decode(
              value as String,
            ).copyWith(reminderEnabled: false).encode();
          }
          rows[entry.key] = value;
        }
        await BackupCodec.writeRows(store.base, box, rows);
        await box.flush();
        if (box.length != rows.length) throw StateError('Incomplete restore');
      }
      for (final image in backup.images.entries) {
        if (!_safeImage(image.key)) {
          throw const FormatException('Invalid image path');
        }
        final file = File('${db.documentsDirectory}/$namespace/${image.key}');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(image.value, flush: true);
      }
    } finally {
      for (final box in opened) {
        await box.close();
      }
    }
    // The old dataset remains intact, even if staging or this rename fails.
    await db.activateRestoredDataset(namespace, backup.activeProfile);
  }
}
