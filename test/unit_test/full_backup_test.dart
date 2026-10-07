import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/data/dbo/profile_dbo.dart';
import 'package:opennutritracker/core/data/dbo/water_intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_gender_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_pal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_weight_goal_dbo.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';
import 'package:opennutritracker/features/cycle/domain/cycle_data.dart';
import 'package:opennutritracker/features/settings/domain/backup/full_backup_service.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String root;
  _Paths(this.root);
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

class _FailStaging extends HiveDBProvider {
  final HiveDBProvider source;
  _FailStaging(this.source) {
    documentsDirectory = source.documentsDirectory;
  }
  @override
  Future<Box<dynamic>> openDataBox(
    String base, {
    String suffix = '',
    String? namespace,
  }) {
    if (base == HiveDBProvider.userBoxName) {
      throw const FileSystemException('Simulated interrupted restore');
    }
    return source.openDataBox(base, suffix: suffix, namespace: namespace);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HiveDBProvider db;
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  var registered = false;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('stable_full_backup_');
    PathProviderPlatform.instance = _Paths(root.path);
    db = HiveDBProvider();
    await db.initHiveDB(key, registerAdapters: !registered);
    registered = true;
    await db.profileBox.put(
      'one',
      ProfileDBO(
        id: 'one',
        name: 'First',
        createdAt: DateTime(2026),
        boxSuffix: '',
        imagePath: 'profile_images/avatar.webp',
      ),
    );
    await db.profileBox.put(
      'two',
      ProfileDBO(
        id: 'two',
        name: 'Second',
        createdAt: DateTime(2026),
        boxSuffix: 'two',
      ),
    );
    await db.openProfileBoxes('one', '');
    await db.userBox.put(
      'user',
      UserDBO(
        birthday: DateTime(1990, 2, 3),
        heightCM: 170,
        weightKG: 65,
        gender: UserGenderDBO.nonBinary,
        goal: UserWeightGoalDBO.loseWeight,
        pal: UserPALDBO.sedentary,
        targetWeightKg: 60,
        caloriesTaperEnabled: true,
      ),
    );
    await db.appConfigBox.put(
      'config',
      ConfigDBO.empty()..notificationsEnabled = true,
    );
    await db.configBox.put(
      'config',
      ConfigDBO.empty()..dailyIntakeLowerKcal = 1800,
    );
    await db.waterIntakeBox.put(
      'sip',
      WaterIntakeDBO(id: 'sip', dateTime: DateTime(2026, 1, 2), amountMl: 250),
    );
    await db.cycleBox.put(
      'data',
      const CycleData(enabled: true, reminderEnabled: true).encode(),
    );
    await db.dailyStepsBox.put('_autoImport', 'true');
    final second = await db.openDataBox(
      HiveDBProvider.waterIntakeBoxName,
      suffix: 'two',
    );
    await second.put(
      'sip2',
      WaterIntakeDBO(id: 'sip2', dateTime: DateTime(2026, 1, 2), amountMl: 350),
    );
    final image = File('${root.path}/profile_images/avatar.webp');
    await image.parent.create();
    await image.writeAsBytes([1, 2, 3, 4]);
  });
  tearDown(() async {
    db.dispose();
    await Hive.close();
    UserImageStorage.resetDocumentsPathCache();
    await root.delete(recursive: true);
  });

  test(
    'round trip stages every profile without modifying the running dataset',
    () async {
      final service = FullBackupService(db);
      final backup = service.inspect(await service.export());
      expect(backup.profileCount, 2);
      await service.restore(backup);
      expect(db.restorePending, isTrue);
      expect(db.dataset, isEmpty);
      expect(db.waterIntakeBox.get('sip')!.amountMl, 250);
      expect(db.appConfigBox.get('config')!.notificationsEnabled, isTrue);
      await Hive.close();
      db.dispose();
      db = HiveDBProvider();
      await db.initHiveDB(key, registerAdapters: !registered);
      registered = true;
      expect(db.dataset, startsWith('restore_'));
      expect(db.restoredActiveProfileId, 'one');
      await db.openProfileBoxes('one', '');
      expect(db.userBox.get('user')!.birthday, DateTime(1990, 2, 3));
      expect(db.userBox.get('user')!.caloriesTaperEnabled, isTrue);
      expect(db.configBox.get('config')!.dailyIntakeLowerKcal, 1800);
      expect(db.waterIntakeBox.get('sip')!.amountMl, 250);
      expect(db.appConfigBox.get('config')!.notificationsEnabled, isFalse);
      expect(CycleData.decode(db.cycleBox.get('data')!).enabled, isTrue);
      expect(
        CycleData.decode(db.cycleBox.get('data')!).reminderEnabled,
        isFalse,
      );
      expect(db.dailyStepsBox.get('_autoImport'), 'false');
      expect(
        await File(
          await UserImageStorage.absolutePath('profile_images/avatar.webp'),
        ).readAsBytes(),
        [1, 2, 3, 4],
      );
      await db.switchProfile('two', 'two');
      expect(db.waterIntakeBox.get('sip2')!.amountMl, 350);
      expect(db.waterIntakeBox.containsKey('sip'), isFalse);
    },
  );

  test(
    'interrupted staging never activates or modifies the old data',
    () async {
      final service = FullBackupService(db);
      final backup = service.inspect(await service.export());
      final failing = _FailStaging(db);
      await expectLater(
        FullBackupService(failing).restore(backup),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File('${root.path}/stable_dataset.json').exists(), isFalse);
      expect(db.userBox.get('user')!.targetWeightKg, 60);
      expect(db.waterIntakeBox.get('sip')!.amountMl, 250);
      failing.dispose();
    },
  );

  test('rejects incomplete stores and unsafe paths before writes', () async {
    final service = FullBackupService(db);
    final original = ZipDecoder().decodeBytes(await service.export());
    final manifest = original.findFile(FullBackupService.manifestName)!;
    final json = jsonDecode(utf8.decode(manifest.content as List<int>)) as Map;
    (json['stores'] as List).removeLast();
    final bytes = utf8.encode(jsonEncode(json));
    final invalid = Archive()
      ..addFile(
        ArchiveFile(FullBackupService.manifestName, bytes.length, bytes),
      );
    expect(
      () => service.inspect(ZipEncoder().encode(invalid)),
      throwsA(isA<FormatException>()),
    );
    final unsafe = Archive()..addFile(ArchiveFile('../escape', 1, [1]));
    expect(
      () => service.inspect(ZipEncoder().encode(unsafe)),
      throwsFormatException,
    );
    expect(db.waterIntakeBox.get('sip')!.amountMl, 250);
    expect(await File('${root.path}/stable_dataset.json').exists(), isFalse);
  });
}
