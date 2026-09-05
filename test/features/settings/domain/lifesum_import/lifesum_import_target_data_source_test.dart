import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_dbo.dart';
import 'package:opennutritracker/core/data/dbo/body_measurement_log_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/dbo/water_intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/weight_log_dbo.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/features/settings/data/lifesum_import/lifesum_import_journal_data_source.dart';
import 'package:opennutritracker/features/settings/data/lifesum_import/lifesum_import_target_data_source.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_executor.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_journal.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_manifest.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_preview.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_tracked_day_plan.dart';

import '../../../../fixture/lifesum_export_fixture.dart';
import '../../../../helpers/fake_hive_db_provider.dart';
import '../../../../helpers/hive_test_setup.dart';

void main() {
  late Directory temporaryDirectory;
  late Box<IntakeDBO> intakeBox;
  late Box<UserActivityDBO> activityBox;
  late Box<TrackedDayDBO> trackedDayBox;
  late Box<WeightLogDBO> weightBox;
  late Box<BodyMeasurementLogDBO> bodyMeasurementBox;
  late Box<WaterIntakeDBO> waterBox;
  late Box<String> journalBox;
  late FakeHiveDBProvider provider;
  late LifesumImportTargetDataSource targets;
  late LifesumImportJournalDataSource journals;
  late LifesumImportManifest manifest;

  List<int> boxLengths() => <int>[
    weightBox.length,
    bodyMeasurementBox.length,
    trackedDayBox.length,
    intakeBox.length,
    activityBox.length,
    waterBox.length,
  ];

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'stable_lifesum_target_store_',
    );
    Hive.init(temporaryDirectory.path);
    registerHiveAdaptersOnce();
    intakeBox = await Hive.openBox<IntakeDBO>('intakes');
    activityBox = await Hive.openBox<UserActivityDBO>('activities');
    trackedDayBox = await Hive.openBox<TrackedDayDBO>('tracked_days');
    weightBox = await Hive.openBox<WeightLogDBO>('weights');
    bodyMeasurementBox = await Hive.openBox<BodyMeasurementLogDBO>(
      'measurements',
    );
    waterBox = await Hive.openBox<WaterIntakeDBO>('water');
    journalBox = await Hive.openBox<String>(
      'journals',
      encryptionCipher: HiveAesCipher(List<int>.filled(32, 7)),
    );
    provider = FakeHiveDBProvider(
      activeProfileId: 'profile-a',
      activeProfileGeneration: 1,
      intakeBox: intakeBox,
      userActivityBox: activityBox,
      trackedDayBox: trackedDayBox,
      weightLogBox: weightBox,
      bodyMeasurementLogBox: bodyMeasurementBox,
      waterIntakeBox: waterBox,
      lifesumImportJournalBox: journalBox,
    );
    targets = LifesumImportTargetDataSource(provider);
    journals = LifesumImportJournalDataSource(provider);
    manifest = _buildManifest(temporaryDirectory);
  });

  tearDown(() async {
    await Hive.close();
    temporaryDirectory.deleteSync(recursive: true);
  });

  group('LifesumImportTargetDataSource', () {
    test(
      'imports 8000 synthetic foods with bounded journal writes',
      () async {
        final foodLines = sanitizedLifesumFiles['food.csv']!.split('\n');
        final zip = writeSanitizedLifesumZip(
          temporaryDirectory,
          files: {
            'food.csv':
                '${foodLines.first}\n${List.filled(8000, foodLines[1]).join('\n')}\n',
          },
        );
        final preview = LifesumImportPreview.fromSelection(
          const LifesumArchiveReader().readCsvSectionsPath(zip.path, {
            LifesumExportSection.food,
          }),
        );
        final primary = LifesumImportManifest.fromPreview(preview);
        final large = LifesumTrackedDayPlan.fromManifest(
          primary,
          goals: LifesumHistoricalGoalSnapshot(
            calorieGoal: 2000,
            carbsGoal: 300,
            fatGoal: 55,
            proteinGoal: 75,
          ),
        ).completeManifest(primary);
        var writtenBytes = 0;
        var largestTransition = 0;
        final subscription = journalBox.watch().listen((event) {
          if (event.deleted) return;
          final size = (event.value as String).length;
          writtenBytes += size;
          if (event.key.toString().contains(':step:') &&
              size > largestTransition) {
            largestTransition = size;
          }
        });
        final stopwatch = Stopwatch()..start();
        final completed = await LifesumImportExecutor(
          journals: journals,
          targets: targets,
        ).execute(large);
        stopwatch.stop();
        await subscription.cancel();
        expect(completed.phase, LifesumImportJournalPhase.completed);
        expect(intakeBox.length, 8000);
        expect(completed.operationCount, 8001);
        expect(largestTransition, lessThan(300));
        expect(writtenBytes, lessThan(large.operationCount * 700));
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 60)));
        final restored = await LifesumImportJournalDataSource(
          provider,
        ).load(large);
        expect(restored?.toJson(), completed.toJson());
        // Aggregate-only benchmark output: no personal archive or profile used.
        // ignore: avoid_print
        print(
          'Synthetic ${large.operationCount}-operation import: ${stopwatch.elapsedMilliseconds} ms, $writtenBytes journal bytes',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'index tracks legacy duplicates, replacement IDs, and deletion',
      () async {
        final operation = manifest.operations
            .whereType<LifesumIntakeImportOperation>()
            .single;
        expect(await targets.probe(operation), LifesumImportTargetProbe.absent);
        final dbo = IntakeDBO.fromIntakeEntity(operation.entry);
        await intakeBox.put(42, dbo);
        expect(
          await targets.probe(operation),
          LifesumImportTargetProbe.matching,
        );
        await intakeBox.put(43, IntakeDBO.fromIntakeEntity(operation.entry));
        expect(
          await targets.probe(operation),
          LifesumImportTargetProbe.conflicting,
        );
        await intakeBox.delete(42);
        expect(
          await targets.probe(operation),
          LifesumImportTargetProbe.matching,
        );
        final other = IntakeEntity(
          id: 'different-id',
          unit: operation.entry.unit,
          amount: operation.entry.amount,
          type: operation.entry.type,
          meal: operation.entry.meal,
          dateTime: operation.entry.dateTime,
        );
        await intakeBox.put(43, IntakeDBO.fromIntakeEntity(other));
        expect(await targets.probe(operation), LifesumImportTargetProbe.absent);
        await intakeBox.put(
          operation.entry.id,
          IntakeDBO.fromIntakeEntity(other),
        );
        expect(
          await targets.probe(operation),
          LifesumImportTargetProbe.conflicting,
        );
        await intakeBox.clear();
        expect(await targets.probe(operation), LifesumImportTargetProbe.absent);
      },
    );

    test(
      'resumes a persisted ambiguous target after reopening the journal',
      () async {
        var journal = LifesumImportJournal.prepare(manifest);
        await journals.save(journal);
        journal = journal.beginApply();
        await journals.save(journal);
        final first = manifest.operations.first;
        journal = journal.markOperationApplying(first.operationId);
        await journals.save(journal);
        await targets.apply(first);
        // Reopening the journal verifies disk persistence independently of the
        // data source's cached lineage; target matching verifies crash recovery.
        await journalBox.close();
        journalBox = await Hive.openBox<String>(
          'journals',
          encryptionCipher: HiveAesCipher(List<int>.filled(32, 7)),
        );
        final resumedProvider = FakeHiveDBProvider(
          lifesumImportJournalBox: journalBox,
        );
        final resumed = await LifesumImportExecutor(
          journals: LifesumImportJournalDataSource(resumedProvider),
          targets: targets,
        ).execute(manifest);
        expect(resumed.phase, LifesumImportJournalPhase.completed);
        expect(
          resumed.operationProgress[first.operationId],
          LifesumImportOperationProgress.applied,
        );
        expect(boxLengths(), everyElement(1));
      },
    );

    test(
      'round-trips every operation kind through isolated Hive boxes',
      () async {
        expect(
          manifest.operations.map((operation) => operation.kind).toSet(),
          LifesumImportOperationKind.values.toSet(),
        );

        for (final operation in manifest.operations) {
          expect(
            await targets.probe(operation),
            LifesumImportTargetProbe.absent,
          );
          await targets.apply(operation);
          expect(
            await targets.probe(operation),
            LifesumImportTargetProbe.matching,
          );
        }
        expect(boxLengths(), everyElement(1));

        for (final operation in manifest.operations.reversed) {
          await targets.rollback(operation);
          expect(
            await targets.probe(operation),
            LifesumImportTargetProbe.absent,
          );
        }
        expect(boxLengths(), everyElement(0));
      },
    );

    test(
      'executor preserves an exact pre-existing Hive target on rerun',
      () async {
        final preserved = manifest.operations.first;
        await targets.apply(preserved);
        final executor = LifesumImportExecutor(
          journals: journals,
          targets: targets,
        );

        final completed = await executor.execute(manifest);
        final repeated = await executor.execute(manifest);

        expect(completed.phase, LifesumImportJournalPhase.completed);
        expect(repeated.toJson(), completed.toJson());
        expect(
          completed.operationProgress[preserved.operationId],
          LifesumImportOperationProgress.preserved,
        );
        for (final operation in manifest.operations) {
          expect(
            await targets.probe(operation),
            LifesumImportTargetProbe.matching,
          );
        }
      },
    );

    test(
      'executor reverses prior real Hive writes after a later failure',
      () async {
        final failingOperation = manifest.operations.last;
        final failingTargets = _FailingTargetStore(
          targets,
          failingOperationId: failingOperation.operationId,
        );
        final executor = LifesumImportExecutor(
          journals: journals,
          targets: failingTargets,
        );

        final rolledBack = await executor.execute(manifest);

        expect(rolledBack.phase, LifesumImportJournalPhase.rolledBack);
        expect(
          failingTargets.rollbackOperationIds,
          manifest.operations
              .take(manifest.operations.length - 1)
              .map((operation) => operation.operationId)
              .toList()
              .reversed,
        );
        for (final operation in manifest.operations) {
          expect(
            await targets.probe(operation),
            LifesumImportTargetProbe.absent,
          );
        }
      },
    );

    test('does not overwrite an occupied calendar-day target', () async {
      final operation = manifest.operations
          .whereType<LifesumWeightImportOperation>()
          .single;
      final conflicting = WeightLogDBO.fromWeightLogEntity(
        WeightLogEntity(
          date: operation.entry.date,
          weightKg: operation.entry.weightKg + 1,
          note: operation.entry.note,
        ),
      );
      await weightBox.put(operation.entry.date.toParsedDay(), conflicting);

      expect(
        await targets.probe(operation),
        LifesumImportTargetProbe.conflicting,
      );
      await expectLater(
        targets.apply(operation),
        _throwsTargetError(LifesumImportTargetStoreFailure.targetNotAbsent),
      );
      expect(
        weightBox.get(operation.entry.date.toParsedDay())?.weightKg,
        conflicting.weightKg,
      );
    });

    test('does not roll back an imported record after it was edited', () async {
      final operation = manifest.operations
          .whereType<LifesumIntakeImportOperation>()
          .single;
      await targets.apply(operation);
      final stored = intakeBox.get(operation.entry.id)!;
      await intakeBox.put(
        operation.entry.id,
        IntakeDBO.fromIntakeEntity(
          IntakeEntity(
            id: stored.id,
            unit: stored.unit,
            amount: stored.amount + 1,
            type: operation.entry.type,
            meal: operation.entry.meal,
            dateTime: stored.dateTime,
          ),
        ),
      );

      expect(
        await targets.probe(operation),
        LifesumImportTargetProbe.conflicting,
      );
      await expectLater(
        targets.rollback(operation),
        _throwsTargetError(LifesumImportTargetStoreFailure.targetChanged),
      );
      expect(intakeBox.get(operation.entry.id)?.amount, stored.amount + 1);
    });

    test('rejects the captured session after a profile switch', () async {
      provider.simulateProfileSwitch(profileId: 'profile-b', generation: 2);

      await expectLater(
        targets.probe(manifest.operations.first),
        _throwsTargetError(LifesumImportTargetStoreFailure.profileChanged),
      );
      await expectLater(
        journals.save(LifesumImportJournal.prepare(manifest)),
        throwsA(
          isA<LifesumImportJournalStoreException>().having(
            (exception) => exception.failure,
            'failure',
            LifesumImportJournalStoreFailure.profileChanged,
          ),
        ),
      );
      expect(boxLengths(), everyElement(0));
      expect(journalBox, isEmpty);
    });
  });
}

LifesumImportManifest _buildManifest(Directory directory) {
  final zip = writeSanitizedLifesumZip(directory);
  final selection = const LifesumArchiveReader().readCsvSectionsPath(
    zip.path,
    LifesumExportSection.values.toSet(),
  );
  final preview = LifesumImportPreview.fromSelection(selection);
  final primary = LifesumImportManifest.fromPreview(
    preview,
    selection: const LifesumImportSelection(includeEstimatedWater: true),
  );
  return LifesumTrackedDayPlan.fromManifest(
    primary,
    goals: LifesumHistoricalGoalSnapshot(
      calorieGoal: 2000,
      carbsGoal: 300,
      fatGoal: 55,
      proteinGoal: 75,
    ),
  ).completeManifest(primary);
}

class _FailingTargetStore implements LifesumImportTargetStore {
  _FailingTargetStore(this.inner, {required this.failingOperationId});

  final LifesumImportTargetStore inner;
  final String failingOperationId;
  final List<String> rollbackOperationIds = <String>[];

  @override
  Future<void> apply(LifesumImportOperation operation) {
    if (operation.operationId == failingOperationId) {
      throw StateError('synthetic target failure');
    }
    return inner.apply(operation);
  }

  @override
  Future<LifesumImportTargetProbe> probe(LifesumImportOperation operation) =>
      inner.probe(operation);

  @override
  Future<void> rollback(LifesumImportOperation operation) {
    rollbackOperationIds.add(operation.operationId);
    return inner.rollback(operation);
  }
}

Matcher _throwsTargetError(LifesumImportTargetStoreFailure failure) => throwsA(
  isA<LifesumImportTargetStoreException>().having(
    (exception) => exception.failure,
    'failure',
    failure,
  ),
);
