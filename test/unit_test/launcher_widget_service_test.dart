import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/utils/launcher_widget_service.dart';
import 'package:opennutritracker/core/utils/locator.dart';

class _Profiles extends Fake implements GetProfilesUsecase {
  String active = 'first';
  @override
  String get activeProfileId => active;
  @override
  ProfileEntity getActiveProfile() => ProfileEntity(
    id: active,
    name: active,
    createdAt: DateTime(2026),
    boxSuffix: active,
  );
}

class _Water extends Fake implements AddWaterIntakeUsecase {
  final saved = <String, WaterIntakeEntity>{};
  @override
  Future<void> addEntry(WaterIntakeEntity entry) async =>
      saved[entry.id] = entry;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  late _Profiles profiles;
  late _Water water;
  late List<Map<String, Object>> queue;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    profiles = _Profiles();
    water = _Water();
    locator.registerSingleton<GetProfilesUsecase>(profiles);
    locator.registerSingleton<AddWaterIntakeUsecase>(water);
    calls.clear();
    queue = [
      {
        'id': 'widget-water-one',
        'profileId': 'first',
        'time': DateTime(2026, 9, 22, 2, 15).millisecondsSinceEpoch,
        'amountMl': 300,
      },
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LauncherWidgetService.channel, (call) async {
          calls.add(call);
          if (call.method == 'pendingWater') return queue;
          if (call.method == 'consumeAction') return 'food';
          return true;
        });
  });

  tearDown(() async {
    await LauncherWidgetService.clear(discardWater: true);
    await locator.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LauncherWidgetService.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> publish({
    String profile = 'first',
    int? revision,
    List<String> ids = const [],
  }) => LauncherWidgetService.publish(
    expectedProfileId: profile,
    expectedRevision: revision ?? LauncherWidgetService.revision,
    appliedWaterIds: ids,
    config: const ConfigEntity(
      false,
      false,
      false,
      AppThemeEntity.dark,
      usesKilojoules: true,
      selectedLocale: 'en',
      dayStartOffsetHours: 4,
      dayStartOffsetMinutes: 30,
    ),
    day: DateTime(2026, 9, 21),
    waterMl: 300,
    waterGoalMl: 2100,
    cupMl: 300,
    foodKcal: 340,
    exerciseKcal: 120,
  );

  test(
    'water imports retain the tap time, cup size and stable ID across retries',
    () async {
      final ids = await LauncherWidgetService.importWater();
      await LauncherWidgetService.importWater();
      expect(ids, ['widget-water-one']);
      expect(water.saved, hasLength(1));
      expect(water.saved.values.single.amountMl, 300);
      expect(water.saved.values.single.dateTime, DateTime(2026, 9, 22, 2, 15));
      expect(
        calls.where((call) => call.method == 'publish'),
        isEmpty,
        reason: 'Do not acknowledge before totals include the imported cup',
      );
      await publish(ids: ids);
      final snapshot = calls.last.arguments as Map;
      expect(snapshot['appliedWaterIds'], ids);
      expect(snapshot['waterMl'], 300);
      expect(snapshot['day'], '2026-9-21');
      expect(snapshot['offsetMinutes'], 270);
      expect(snapshot['foodValue'], '1423 kJ');
      expect(snapshot['exerciseValue'], '502 kJ');
      expect(snapshot['theme'], 'dark');
    },
  );

  test('another profile cannot receive queued water or stale totals', () async {
    profiles.active = 'other';
    expect(await LauncherWidgetService.importWater(), isEmpty);
    expect(water.saved, isEmpty);
    await publish(profile: 'first');
    expect(calls.where((call) => call.method == 'publish'), isEmpty);
  });

  test(
    'deletion prevents an in-flight load from restoring deleted totals',
    () async {
      final oldRevision = LauncherWidgetService.revision;
      await LauncherWidgetService.clear(discardWater: true);
      await publish(revision: oldRevision);
      expect(calls.where((call) => call.method == 'publish'), isEmpty);
      final clear = calls.first.arguments as Map;
      expect(clear['discardWater'], true);
      expect(clear['profileId'], 'first');
    },
  );

  test('only IDs captured by this load are acknowledged', () async {
    final first = await LauncherWidgetService.importWater();
    queue.add({
      'id': 'widget-water-two',
      'profileId': 'first',
      'time': DateTime(2026, 9, 22, 2, 16).millisecondsSinceEpoch,
      'amountMl': 300,
    });
    await LauncherWidgetService.importWater();
    await publish(ids: first);
    expect((calls.last.arguments as Map)['appliedWaterIds'], [
      'widget-water-one',
    ]);
  });

  test('cold-start action is read through the native bridge', () async {
    expect(await LauncherWidgetService.consumeAction(), 'food');
    expect(calls.single.method, 'consumeAction');
  });
}
