import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_existing_history_loader.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_coordinator.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_executor.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_journal.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_manifest.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_tracked_day_plan.dart';

import '../../../../fixture/lifesum_export_fixture.dart';
import '../../../../helpers/fake_hive_db_provider.dart';

void main() {
  late Directory temporaryDirectory;
  late File archive;
  late FakeHiveDBProvider database;
  late _MemoryJournalStore journals;
  late _MemoryTargetStore targets;
  late _TestPicker picker;
  late LifesumExistingHistoryLoader historyLoader;
  late LifesumImportCoordinator coordinator;
  var historyLoadCount = 0;
  var settingsLoadCount = 0;
  var executorCreateCount = 0;

  LifesumImportCoordinator buildCoordinator({
    LifesumArchivePicker? archivePicker,
  }) => LifesumImportCoordinator(
    database: database,
    picker: archivePicker ?? picker,
    historyLoader: historyLoader,
    loadSettings: () async {
      settingsLoadCount++;
      return LifesumImportSettingsSnapshot(
        dayStartOffsetMinutes: 0,
        historicalGoals: LifesumHistoricalGoalSnapshot(
          calorieGoal: 2000,
          carbsGoal: 300,
          fatGoal: 55,
          proteinGoal: 75,
        ),
      );
    },
    createExecutor: () {
      executorCreateCount++;
      return LifesumImportExecutor(journals: journals, targets: targets);
    },
  );

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'stable_lifesum_coordinator_',
    );
    archive = writeSanitizedLifesumZip(temporaryDirectory);
    database = FakeHiveDBProvider(
      activeProfileId: 'profile-a',
      activeProfileGeneration: 1,
    );
    journals = _MemoryJournalStore();
    targets = _MemoryTargetStore();
    picker = _TestPicker(archive.path);
    historyLoadCount = 0;
    settingsLoadCount = 0;
    executorCreateCount = 0;
    historyLoader = LifesumExistingHistoryLoader(
      activeProfileId: () => database.activeProfileId,
      activeProfileGeneration: () => database.activeProfileGeneration,
      loadIntakes: () async {
        historyLoadCount++;
        return const <IntakeEntity>[];
      },
      loadActivities: () async => const <UserActivityEntity>[],
      loadWeights: () async => const <WeightLogEntity>[],
      loadBodyMeasurements: () async => const <BodyMeasurementLogEntity>[],
      loadTrackedDays: () async => const <TrackedDayEntity>[],
      loadWaterEntries: () async => const <WaterIntakeEntity>[],
      loadRecipes: () async => const <RecipeEntity>[],
    );
    coordinator = buildCoordinator();
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  group('LifesumImportCoordinator', () {
    test('picker cancellation is a no-op', () async {
      final cancelled = buildCoordinator(archivePicker: _TestPicker(null));

      expect(await cancelled.chooseArchive(), isNull);
      expect(historyLoadCount, 0);
      expect(settingsLoadCount, 0);
      expect(executorCreateCount, 0);
      expect(targets.values, isEmpty);
      expect(journals.values, isEmpty);
    });

    test(
      'prepares a read-only review with estimated water default-off',
      () async {
        final preparation = await coordinator.chooseArchive();

        expect(preparation, isNotNull);
        expect(preparation!.profileId, 'profile-a');
        expect(preparation.preview.readyToAddCount, 4);
        expect(preparation.preview.estimatedWaterCandidateCount, 1);
        expect(
          preparation.operationCountFor(const LifesumImportSelection()),
          5,
        );
        expect(
          preparation.operationCountFor(
            const LifesumImportSelection(includeEstimatedWater: true),
          ),
          6,
        );
        expect(preparation.confirmationStarted, isFalse);
        expect(historyLoadCount, 1);
        expect(settingsLoadCount, 1);
        expect(executorCreateCount, 0);
        expect(targets.values, isEmpty);
        expect(journals.values, isEmpty);
        expect(preparation.toString(), isNot(contains(archive.path)));
      },
    );

    test('confirms once after an unchanged second read', () async {
      final preparation = (await coordinator.chooseArchive())!;

      final completed = await coordinator.confirm(preparation);

      expect(completed.phase, LifesumImportJournalPhase.completed);
      expect(completed.operationCount, 5);
      expect(
        targets.values.values.map((operation) => operation.kind),
        isNot(contains(LifesumImportOperationKind.estimatedWater)),
      );
      expect(historyLoadCount, 2);
      expect(settingsLoadCount, 2);
      expect(executorCreateCount, 1);
      expect(preparation.confirmationStarted, isTrue);
      await expectLater(
        coordinator.confirm(preparation),
        _throwsCoordinatorError(
          LifesumImportCoordinatorFailure.alreadyConfirmed,
        ),
      );
      expect(executorCreateCount, 1);
    });

    test('adds estimated water only after explicit confirmation', () async {
      final preparation = (await coordinator.chooseArchive())!;

      final completed = await coordinator.confirm(
        preparation,
        selection: const LifesumImportSelection(includeEstimatedWater: true),
      );

      expect(completed.operationCount, 6);
      expect(
        targets.values.values.map((operation) => operation.kind),
        contains(LifesumImportOperationKind.estimatedWater),
      );
    });

    test('rejects switch-away-and-back after preview without writes', () async {
      final preparation = (await coordinator.chooseArchive())!;
      database.simulateProfileSwitch(profileId: 'profile-a', generation: 3);

      await expectLater(
        coordinator.confirm(preparation),
        _throwsCoordinatorError(
          LifesumImportCoordinatorFailure.activeProfileChanged,
        ),
      );
      expect(executorCreateCount, 0);
      expect(targets.values, isEmpty);
      expect(journals.values, isEmpty);
    });

    test('rejects an archive changed after preview without writes', () async {
      final preparation = (await coordinator.chooseArchive())!;
      writeSanitizedLifesumZip(
        temporaryDirectory,
        files: <String, String>{
          ...sanitizedLifesumFiles,
          'food.csv': sanitizedLifesumFiles['food.csv']!.replaceFirst(
            ',300,50,',
            ',301,50,',
          ),
        },
      );

      await expectLater(
        coordinator.confirm(preparation),
        _throwsCoordinatorError(LifesumImportCoordinatorFailure.previewChanged),
      );
      expect(executorCreateCount, 0);
      expect(targets.values, isEmpty);
      expect(journals.values, isEmpty);
    });

    test('rejects a preparation owned by another coordinator', () async {
      final preparation = (await coordinator.chooseArchive())!;
      final other = buildCoordinator();

      await expectLater(
        other.confirm(preparation),
        _throwsCoordinatorError(
          LifesumImportCoordinatorFailure.foreignPreparation,
        ),
      );
      expect(executorCreateCount, 0);
    });
  });
}

class _TestPicker implements LifesumArchivePicker {
  const _TestPicker(this.path);

  final String? path;

  @override
  Future<String?> pickArchivePath() async => path;
}

class _MemoryJournalStore implements LifesumImportJournalStore {
  final Map<String, LifesumImportJournal> values =
      <String, LifesumImportJournal>{};

  @override
  Future<LifesumImportJournal?> load(LifesumImportManifest manifest) async =>
      values[manifest.manifestId];

  @override
  Future<void> save(LifesumImportJournal journal) async {
    values[journal.manifestId] = journal;
  }
}

class _MemoryTargetStore implements LifesumImportTargetStore {
  final Map<String, LifesumImportOperation> values =
      <String, LifesumImportOperation>{};

  @override
  Future<LifesumImportTargetProbe> probe(
    LifesumImportOperation operation,
  ) async {
    final existing = values[operation.targetKey];
    if (existing == null) return LifesumImportTargetProbe.absent;
    return existing.operationId == operation.operationId
        ? LifesumImportTargetProbe.matching
        : LifesumImportTargetProbe.conflicting;
  }

  @override
  Future<void> apply(LifesumImportOperation operation) async {
    values[operation.targetKey] = operation;
  }

  @override
  Future<void> rollback(LifesumImportOperation operation) async {
    values.remove(operation.targetKey);
  }
}

Matcher _throwsCoordinatorError(LifesumImportCoordinatorFailure failure) =>
    throwsA(
      isA<LifesumImportCoordinatorException>().having(
        (exception) => exception.failure,
        'failure',
        failure,
      ),
    );
