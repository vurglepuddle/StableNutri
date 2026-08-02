import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';

import '../helpers/fake_hive_db_provider.dart';
import '../helpers/hive_test_setup.dart';

void main() {
  group('ConfigDataSource Stable targets', () {
    late Box<ConfigDBO> appBox;
    late Box<ConfigDBO> profileBox;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      registerHiveAdaptersOnce();
    });

    setUp(() async {
      Hive.init('.');
      final suffix = DateTime.now().microsecondsSinceEpoch;
      appBox = await Hive.openBox<ConfigDBO>('stable_targets_app_$suffix');
      profileBox = await Hive.openBox<ConfigDBO>(
        'stable_targets_profile_$suffix',
      );
      await appBox.put('ConfigKey', ConfigDBO.empty());
      await profileBox.put('ConfigKey', ConfigDBO.empty());
    });

    tearDown(() async {
      await appBox.deleteFromDisk();
      await profileBox.deleteFromDisk();
    });

    test('both ranges survive a data-source round trip', () async {
      final source = ConfigDataSource(
        FakeHiveDBProvider(configBox: profileBox, appConfigBox: appBox),
      );

      await source.setConfigDailyIntakeRange(1850, 2100);
      await source.setConfigWeightCorridor(66, 70);

      final reloaded = ConfigDataSource(
        FakeHiveDBProvider(configBox: profileBox, appConfigBox: appBox),
      );
      final config = ConfigEntity.fromConfigDBO(await reloaded.getConfig());

      expect(config.dailyIntakeLowerKcal, 1850);
      expect(config.dailyIntakeUpperKcal, 2100);
      expect(config.weightCorridorLowerKg, 66);
      expect(config.weightCorridorUpperKg, 70);
    });

    test(
      'profile overlay does not leak ranges from the shared app box',
      () async {
        final firstProfile = ConfigDataSource(
          FakeHiveDBProvider(configBox: profileBox, appConfigBox: appBox),
        );
        await firstProfile.setConfigDailyIntakeRange(1850, 2100);
        await firstProfile.setConfigWeightCorridor(66, 70);

        final secondProfileBox = await Hive.openBox<ConfigDBO>(
          'stable_targets_profile_2_${DateTime.now().microsecondsSinceEpoch}',
        );
        addTearDown(secondProfileBox.deleteFromDisk);
        await secondProfileBox.put('ConfigKey', ConfigDBO.empty());

        final secondProfile = ConfigDataSource(
          FakeHiveDBProvider(configBox: secondProfileBox, appConfigBox: appBox),
        );
        final config = ConfigEntity.fromConfigDBO(
          await secondProfile.getConfig(),
        );

        expect(config.dailyIntakeLowerKcal, isNull);
        expect(config.dailyIntakeUpperKcal, isNull);
        expect(config.weightCorridorLowerKg, isNull);
        expect(config.weightCorridorUpperKg, isNull);
      },
    );
  });
}
