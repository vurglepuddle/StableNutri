import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';

import '../helpers/fake_hive_db_provider.dart';
import '../helpers/hive_test_setup.dart';

/// Show Water Tracking is a shared view toggle like Show Activity Tracking:
/// on by default, stored in its own Hive field, and the same for every
/// profile on the device.
void main() {
  late Box<ConfigDBO> appBox;
  late Box<ConfigDBO> profileBox;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerHiveAdaptersOnce();
  });

  setUp(() async {
    Hive.init('.');
    final suffix = DateTime.now().microsecondsSinceEpoch;
    appBox = await Hive.openBox<ConfigDBO>('water_toggle_app_$suffix');
    profileBox = await Hive.openBox<ConfigDBO>('water_toggle_profile_$suffix');
    await appBox.put('ConfigKey', ConfigDBO.empty());
    await profileBox.put('ConfigKey', ConfigDBO.empty());
  });

  tearDown(() async {
    await appBox.deleteFromDisk();
    await profileBox.deleteFromDisk();
  });

  ConfigDataSource source(Box<ConfigDBO> profile) => ConfigDataSource(
    FakeHiveDBProvider(configBox: profile, appConfigBox: appBox),
  );

  test('existing configs show water', () async {
    final config = ConfigEntity.fromConfigDBO(
      await source(profileBox).getConfig(),
    );
    expect(config.showWaterTracking, isTrue);
  });

  test('turning water off survives a reopened box', () async {
    await source(profileBox).setConfigShowWaterTracking(false);
    await appBox.close();
    appBox = await Hive.openBox<ConfigDBO>(appBox.name);

    final config = ConfigEntity.fromConfigDBO(
      await source(profileBox).getConfig(),
    );
    expect(config.showWaterTracking, isFalse);
  });

  test('the setting is shared by every profile', () async {
    await source(profileBox).setConfigShowWaterTracking(false);
    final otherProfile = await Hive.openBox<ConfigDBO>(
      'water_toggle_other_${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(otherProfile.deleteFromDisk);
    await otherProfile.put('ConfigKey', ConfigDBO.empty());

    final config = ConfigEntity.fromConfigDBO(
      await source(otherProfile).getConfig(),
    );
    expect(config.showWaterTracking, isFalse);
  });
}
