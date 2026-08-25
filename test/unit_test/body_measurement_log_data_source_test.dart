import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/body_measurement_log_data_source.dart';
import 'package:opennutritracker/core/data/dbo/body_measurement_log_dbo.dart';

import '../helpers/fake_hive_db_provider.dart';
import '../helpers/hive_test_setup.dart';

void main() {
  group('BodyMeasurementLogDataSource', () {
    late Box<BodyMeasurementLogDBO> box;
    late BodyMeasurementLogDataSource dataSource;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      registerHiveAdaptersOnce();
    });

    setUp(() async {
      Hive.init('.');
      box = await Hive.openBox<BodyMeasurementLogDBO>(
        'body_measurement_test_${DateTime.now().microsecondsSinceEpoch}',
      );
      dataSource = BodyMeasurementLogDataSource(
        FakeHiveDBProvider(bodyMeasurementLogBox: box),
      );
    });

    tearDown(() => box.deleteFromDisk());

    test('round-trips every optional field', () async {
      final entry = BodyMeasurementLogDBO(
        date: DateTime.utc(2026, 8, 20),
        waistCm: 78.2,
        hipsCm: 97.1,
        chestCm: 106.4,
        armCm: 31,
        thighCm: 58.5,
        bodyFatPercent: 21.3,
        note: 'Feeling stronger',
      );

      await dataSource.addEntry(entry);
      final saved = await dataSource.getEntry(entry.date);

      expect(saved, isNotNull);
      expect(saved!.waistCm, 78.2);
      expect(saved.hipsCm, 97.1);
      expect(saved.chestCm, 106.4);
      expect(saved.armCm, 31);
      expect(saved.thighCm, 58.5);
      expect(saved.bodyFatPercent, 21.3);
      expect(saved.note, 'Feeling stronger');
    });

    test('saving the same day updates its snapshot', () async {
      final day = DateTime.utc(2026, 8, 20);
      await dataSource.addEntry(BodyMeasurementLogDBO(date: day, waistCm: 80));
      await dataSource.addEntry(
        BodyMeasurementLogDBO(date: day, waistCm: 79.5),
      );

      expect(await dataSource.allEntries(), hasLength(1));
      expect((await dataSource.getEntry(day))!.waistCm, 79.5);
    });

    test(
      'bulk import and JSON serialization preserve canonical values',
      () async {
        final first = BodyMeasurementLogDBO(
          date: DateTime.utc(2026, 8, 18),
          waistCm: 80,
        );
        final second = BodyMeasurementLogDBO.fromJson(
          BodyMeasurementLogDBO(
            date: DateTime.utc(2026, 8, 20),
            hipsCm: 96.4,
            bodyFatPercent: 20.1,
          ).toJson(),
        );

        await dataSource.addAllEntries([first, second]);

        final all = await dataSource.allEntries();
        expect(all, hasLength(2));
        final restored = all.singleWhere((entry) => entry.date == second.date);
        expect(restored.hipsCm, 96.4);
        expect(restored.bodyFatPercent, 20.1);
      },
    );

    test('range reads are inclusive and deletion is day-scoped', () async {
      final first = DateTime.utc(2026, 8, 18);
      final middle = DateTime.utc(2026, 8, 20);
      final last = DateTime.utc(2026, 8, 22);
      for (final day in [first, middle, last]) {
        await dataSource.addEntry(
          BodyMeasurementLogDBO(date: day, waistCm: 80),
        );
      }

      final range = await dataSource.entriesInRange(first, middle);
      expect(range.map((entry) => entry.date), containsAll([first, middle]));
      expect(range, hasLength(2));

      await dataSource.deleteEntry(middle);
      expect(await dataSource.getEntry(middle), isNull);
      expect(await dataSource.allEntries(), hasLength(2));
    });
  });
}
