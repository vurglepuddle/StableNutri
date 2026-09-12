import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_dbo.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/health/health_connect_service.dart';
import 'package:opennutritracker/core/data/health/health_steps_sync.dart';
import 'package:opennutritracker/core/data/repository/daily_steps_repository.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/daily_steps.dart';

import '../helpers/fake_hive_db_provider.dart';
import '../helpers/hive_test_setup.dart';

class FakeStepsService extends HealthConnectService {
  final calls = <String>[];
  bool granted = true;
  bool unavailable = false;
  int? offset;
  int? lookback;
  List<DailySteps> totals = [];
  Future<List<DailySteps>> Function()? onRead;

  @override
  Future<String> status() async {
    calls.add('status');
    return unavailable ? 'unavailable' : 'available';
  }

  @override
  Future<bool> hasReadPermission() async {
    calls.add('check');
    return granted;
  }

  @override
  Future<bool> requestReadPermissions() async {
    calls.add('prompt');
    return granted;
  }

  @override
  Future<List<DailySteps>> readRecentStepTotals({
    required int offsetMinutes,
    int days = 7,
  }) async {
    calls.add('read');
    offset = offsetMinutes;
    lookback = days;
    return onRead != null ? await onRead!() : totals;
  }
}

void main() {
  late Directory directory;
  late Box<String> stepBox;
  late Box<TrackedDayDBO> dayBox;
  late Box<UserActivityDBO> activityBox;
  late FakeHiveDBProvider db;
  late DailyStepsRepository repository;
  late FakeStepsService service;
  late HealthStepsSync sync;
  late DateTime now;
  late ConfigDBO config;

  DailySteps total({int steps = 5000, int day = 12, DateTime? readAt}) =>
      DailySteps(
        day: DateTime(2026, 9, day),
        steps: steps,
        readAt: readAt ?? now,
        offsetMinutes: 270,
      );

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = Directory.systemTemp.createTempSync('stable_steps_');
    Hive.init(directory.path);
    registerHiveAdaptersOnce();
    stepBox = await Hive.openBox<String>(
      'steps',
      encryptionCipher: HiveAesCipher(List.filled(32, 11)),
    );
    dayBox = await Hive.openBox<TrackedDayDBO>('days');
    activityBox = await Hive.openBox<UserActivityDBO>('activities');
    db = FakeHiveDBProvider(
      activeProfileId: 'a',
      activeProfileGeneration: 1,
      dailyStepsBox: stepBox,
      trackedDayBox: dayBox,
      userActivityBox: activityBox,
    );
    repository = DailyStepsRepository(db);
    service = FakeStepsService();
    now = DateTime(2026, 9, 12, 12);
    config = ConfigDBO.empty()
      ..dayStartOffsetHours = 4
      ..dayStartOffsetMinutes = 30;
    sync = HealthStepsSync(
      db: db,
      repository: repository,
      service: service,
      getConfig: () async => ConfigEntity.fromConfigDBO(config),
      clock: () => now,
    );
  });

  tearDown(() async {
    await Hive.close();
    directory.deleteSync(recursive: true);
  });

  test(
    'disabled profiles never request permission or read health data',
    () async {
      expect(await sync.sync(), StepSyncResult.disabled);
      expect(service.calls, isEmpty);
      expect(repository.all(), isEmpty);
    },
  );

  test(
    'automatic import stores daily steps without calorie or activity changes',
    () async {
      await dayBox.put(
        '2026-09-12',
        TrackedDayDBO(
          day: DateTime(2026, 9, 12),
          calorieGoal: 1900,
          caloriesTracked: 800,
          carbsGoal: 180,
          proteinGoal: 90,
        ),
      );
      final before = jsonEncode(dayBox.values.single.toJson());
      await repository.beginImport().setAutoImport(true);
      service.totals = [total(), total(day: 11, steps: 7200)];
      expect(await sync.sync(), StepSyncResult.updated);
      expect(service.calls, ['status', 'check', 'read']);
      expect(service.offset, 270);
      expect(repository.forDay(DateTime(2026, 9, 12))!.steps, 5000);
      expect(repository.forDay(DateTime(2026, 9, 11))!.steps, 7200);
      expect(activityBox.isEmpty, isTrue);
      expect(jsonEncode(dayBox.values.single.toJson()), before);
    },
  );

  test(
    'refresh replaces counts, including source corrections, without duplication',
    () async {
      await repository.beginImport().setAutoImport(true);
      service.totals = [total()];
      await sync.sync();
      now = now.add(const Duration(minutes: 20));
      service.totals = [total(steps: 6200)];
      await sync.sync();
      expect(repository.all().length, 1);
      expect(repository.all().single.steps, 6200);
      now = now.add(const Duration(minutes: 20));
      service.totals = [total(steps: 5900)];
      await sync.sync();
      expect(repository.all().single.steps, 5900);
    },
  );

  test(
    'revoked permissions never prompt automatically and preserve saved totals',
    () async {
      await repository.beginImport().save([total()]);
      await repository.beginImport().setAutoImport(true);
      service.granted = false;
      expect(await sync.sync(), StepSyncResult.permissionRequired);
      expect(service.calls, ['status', 'check']);
      expect(repository.all().single.steps, 5000);
    },
  );

  test(
    'simultaneous resume events share a read; later reloads are throttled',
    () async {
      await repository.beginImport().setAutoImport(true);
      final read = Completer<List<DailySteps>>();
      service.onRead = () => read.future;
      final a = sync.sync();
      final b = sync.sync();
      read.complete([total()]);
      expect(await a, StepSyncResult.updated);
      expect(await b, StepSyncResult.updated);
      expect(service.calls.where((c) => c == 'read').length, 1);
      now = now.add(const Duration(minutes: 1));
      await sync.sync();
      expect(service.calls.where((c) => c == 'read').length, 1);
    },
  );

  test('a new logical day bypasses the refresh throttle', () async {
    await repository.beginImport().setAutoImport(true);
    now = DateTime(2026, 9, 12, 4, 29);
    service.totals = [total(day: 11)];
    await sync.sync();
    now = DateTime(2026, 9, 12, 4, 30);
    service.totals = [total()];
    await sync.sync();
    expect(service.calls.where((c) => c == 'read').length, 2);
  });

  test('missed days expand catch-up, bounded to 30 days', () async {
    await repository.beginImport().save([total(day: 1)]);
    await repository.beginImport().setAutoImport(true);
    await sync.sync();
    expect(service.lookback, 12);
    now = DateTime(2026, 11, 1);
    await sync.sync(force: true);
    expect(service.lookback, 30);
  });

  test('switching away and back during read cancels all step writes', () async {
    await repository.beginImport().setAutoImport(true);
    service.onRead = () async {
      db.simulateProfileSwitch(profileId: 'b', generation: 2);
      db.simulateProfileSwitch(profileId: 'a', generation: 3);
      return [total()];
    };
    expect(await sync.sync(), StepSyncResult.failed);
    expect(repository.all(), isEmpty);
  });

  test(
    'disabling automatic import during a read discards its response',
    () async {
      await repository.beginImport().setAutoImport(true);
      service.onRead = () async {
        await repository.beginImport().setAutoImport(false);
        return [total()];
      };
      expect(await sync.sync(), StepSyncResult.disabled);
      expect(repository.all(), isEmpty);
    },
  );

  test(
    'changing the day boundary during a read discards the old grouping',
    () async {
      await repository.beginImport().setAutoImport(true);
      service.onRead = () async {
        config.dayStartOffsetMinutes = 0;
        return [total()];
      };
      expect(await sync.sync(), StepSyncResult.failed);
      expect(repository.all(), isEmpty);
    },
  );

  test('provider failures and empty responses keep existing totals', () async {
    await repository.beginImport().save([total()]);
    await repository.beginImport().setAutoImport(true);
    service.onRead = () => throw StateError('provider unavailable');
    expect(await sync.sync(), StepSyncResult.failed);
    service.onRead = null;
    expect(await sync.sync(), StepSyncResult.empty);
    expect(repository.all().single.steps, 5000);
  });

  test(
    'backup rows round-trip without consent; older snapshots cannot overwrite newer ones',
    () async {
      await repository.beginImport().setAutoImport(true);
      await repository.beginImport().save([total()]);
      final backup =
          jsonDecode(
                jsonEncode(
                  repository.all().map((row) => row.toJson()).toList(),
                ),
              )
              as List;
      expect(backup.length, 1);
      expect((backup.single as Map).containsKey('_autoImport'), isFalse);
      await stepBox.clear();
      await repository.beginImport().save(
        backup
            .map(
              (row) =>
                  DailySteps.fromJson(Map<String, dynamic>.from(row as Map)),
            )
            .toList(),
      );
      expect(repository.autoImportEnabled, isFalse);
      await repository.beginImport().save([
        total(steps: 1, readAt: now.subtract(const Duration(hours: 1))),
      ]);
      expect(repository.all().single.steps, 5000);
    },
  );

  test(
    'invalid date, count and offset reject the whole batch before writes',
    () async {
      for (final bad in [
        {...total().toJson(), 'day': '2026-02-31'},
        {...total().toJson(), 'steps': -1},
        {...total().toJson(), 'offsetMinutes': 1440},
      ]) {
        expect(() => DailySteps.fromJson(bad), throwsFormatException);
      }
      await expectLater(
        repository.beginImport().save([total(), total(day: 11, steps: -1)]),
        throwsFormatException,
      );
      expect(repository.all(), isEmpty);
    },
  );
}
