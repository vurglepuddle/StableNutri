import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/features/settings/data/lifesum_import/lifesum_import_journal_data_source.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_journal.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_manifest.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_preview.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_tracked_day_plan.dart';

import '../../../../fixture/lifesum_export_fixture.dart';
import '../../../../helpers/fake_hive_db_provider.dart';

void main() {
  late Directory temporaryDirectory;
  late Box<String> journalBox;
  late LifesumImportJournalDataSource dataSource;
  late LifesumImportManifest manifest;

  setUp(() async {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'stable_lifesum_journal_store_',
    );
    Hive.init(temporaryDirectory.path);
    journalBox = await Hive.openBox<String>('journal');
    dataSource = LifesumImportJournalDataSource(
      FakeHiveDBProvider(lifesumImportJournalBox: journalBox),
    );
    manifest = _buildManifest(temporaryDirectory);
  });

  tearDown(() async {
    await Hive.close();
    temporaryDirectory.deleteSync(recursive: true);
  });

  group('LifesumImportJournalDataSource', () {
    test('round-trips the latest journal without candidate payloads', () async {
      final firstOperation = manifest.operations.first;
      final journal = LifesumImportJournal.prepare(
        manifest,
      ).beginApply().markOperationApplying(firstOperation.operationId);

      await dataSource.save(journal);
      final loaded = await dataSource.load(manifest);
      final latest = await dataSource.loadLatest();

      expect(loaded?.toJson(), journal.toJson());
      expect(latest?.toJson(), journal.toJson());
      final storedValues = journalBox.values.join('\n');
      expect(storedValues, isNot(contains('Example')));
      expect(storedValues, isNot(contains('archive')));
      expect(storedValues, isNot(contains('payload')));
    });

    test('keeps profile boxes isolated', () async {
      final otherBox = await Hive.openBox<String>('journal_other_profile');
      final otherDataSource = LifesumImportJournalDataSource(
        FakeHiveDBProvider(lifesumImportJournalBox: otherBox),
      );
      await dataSource.save(LifesumImportJournal.prepare(manifest));

      expect(await otherDataSource.load(manifest), isNull);
      expect(await otherDataSource.loadLatest(), isNull);
    });

    test('does not replace a different non-terminal import', () async {
      final otherManifest = _buildManifest(
        temporaryDirectory,
        includeEstimatedWater: true,
      );
      await dataSource.save(LifesumImportJournal.prepare(manifest));

      await expectLater(
        dataSource.save(LifesumImportJournal.prepare(otherManifest)),
        throwsA(
          isA<LifesumImportJournalStoreException>().having(
            (exception) => exception.failure,
            'failure',
            LifesumImportJournalStoreFailure.activeImportExists,
          ),
        ),
      );

      await dataSource.save(_completedJournal(manifest));
      await dataSource.save(LifesumImportJournal.prepare(otherManifest));
      expect(
        (await dataSource.loadLatest())?.manifestId,
        otherManifest.manifestId,
      );
    });

    test('deletes both the journal and its latest pointer', () async {
      await dataSource.save(LifesumImportJournal.prepare(manifest));

      await dataSource.delete(manifest.manifestId);

      expect(await dataSource.load(manifest), isNull);
      expect(await dataSource.loadLatest(), isNull);
      expect(journalBox, isEmpty);
    });

    test('rejects corrupt journal JSON and a stale latest pointer', () async {
      await journalBox.put(manifest.manifestId, '{not-json');
      await expectLater(
        dataSource.load(manifest),
        _throwsJournalError(LifesumImportJournalError.invalidSnapshot),
      );

      await journalBox.clear();
      await journalBox.put('_latestManifest', 'missing-manifest');
      await expectLater(
        dataSource.loadLatest(),
        _throwsJournalError(LifesumImportJournalError.invalidSnapshot),
      );
    });
  });
}

LifesumImportManifest _buildManifest(
  Directory directory, {
  bool includeEstimatedWater = false,
}) {
  final zip = writeSanitizedLifesumZip(directory);
  final selection = const LifesumArchiveReader().readCsvSectionsPath(
    zip.path,
    LifesumExportSection.values.toSet(),
  );
  final preview = LifesumImportPreview.fromSelection(selection);
  final primary = LifesumImportManifest.fromPreview(
    preview,
    selection: LifesumImportSelection(
      includeEstimatedWater: includeEstimatedWater,
    ),
  );
  final plan = LifesumTrackedDayPlan.fromManifest(
    primary,
    goals: LifesumHistoricalGoalSnapshot(
      calorieGoal: 2000,
      carbsGoal: 300,
      fatGoal: 55,
      proteinGoal: 75,
    ),
  );
  return plan.completeManifest(primary);
}

LifesumImportJournal _completedJournal(LifesumImportManifest manifest) {
  var journal = LifesumImportJournal.prepare(manifest).beginApply();
  for (final operation in manifest.operations) {
    journal = journal
        .markOperationApplying(operation.operationId)
        .markOperationApplied(operation.operationId);
  }
  return journal.completeApply();
}

Matcher _throwsJournalError(LifesumImportJournalError error) => throwsA(
  isA<LifesumImportJournalException>().having(
    (exception) => exception.error,
    'error',
    error,
  ),
);
