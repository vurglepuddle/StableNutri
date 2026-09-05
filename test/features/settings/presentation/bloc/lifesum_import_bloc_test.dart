import 'dart:async';
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
import 'package:opennutritracker/features/settings/presentation/bloc/lifesum_import_bloc.dart';

import '../../../../fixture/lifesum_export_fixture.dart';
import '../../../../helpers/fake_hive_db_provider.dart';

void main() {
  late _Harness harness;
  late LifesumImportBloc bloc;

  setUp(() {
    harness = _Harness();
    bloc = LifesumImportBloc(harness.coordinator);
  });

  tearDown(() async {
    await bloc.close();
    harness.dispose();
  });

  test('leaving review releases the archive without importing', () async {
    final ready = bloc.stream.firstWhere(
      (state) => state is LifesumImportReady,
    );
    bloc.add(const ChooseLifesumArchiveEvent());
    await ready;
    await bloc.close();
    expect(harness.picker.cleanupCount, 1);
    expect(harness.targets.values, isEmpty);
  });

  test(
    'a picker result arriving after the screen closes is still released',
    () async {
      final pending = Completer<String?>();
      harness.picker.pending = pending;
      final loading = bloc.stream.firstWhere(
        (state) => state is LifesumImportLoading,
      );
      bloc.add(const ChooseLifesumArchiveEvent());
      await loading;
      await bloc.close();
      final released = Completer<void>();
      harness.picker.nextCleanup = released;
      pending.complete(harness.pickedPath);
      await released.future;
      expect(harness.picker.cleanupCount, 2);
      expect(harness.targets.values, isEmpty);
    },
  );

  test(
    'picker cancellation returns to the initial state without writes',
    () async {
      await bloc.close();
      harness.dispose();
      harness = _Harness(cancelPicker: true);
      bloc = LifesumImportBloc(harness.coordinator);
      final expectation = expectLater(
        bloc.stream,
        emitsInOrder(<Object>[
          isA<LifesumImportLoading>(),
          isA<LifesumImportInitial>(),
        ]),
      );

      bloc.add(const ChooseLifesumArchiveEvent());
      await expectation;

      expect(harness.targets.values, isEmpty);
      expect(harness.journals.values, isEmpty);
      expect(harness.executorCreateCount, 0);
    },
  );

  test(
    'loads review, toggles water, and imports only after confirmation',
    () async {
      final readyExpectation = expectLater(
        bloc.stream,
        emitsInOrder(<Object>[
          isA<LifesumImportLoading>(),
          isA<LifesumImportReady>().having(
            (state) => state.selection.includeEstimatedWater,
            'estimated water default',
            isFalse,
          ),
        ]),
      );
      bloc.add(const ChooseLifesumArchiveEvent());
      await readyExpectation;
      expect(harness.targets.values, isEmpty);

      final toggledFuture = bloc.stream.firstWhere(
        (state) =>
            state is LifesumImportReady &&
            state.selection.includeEstimatedWater,
      );
      bloc.add(
        const SetLifesumImportCategoryEvent(
          category: LifesumImportCategory.estimatedWater,
          included: true,
        ),
      );
      final toggled = await toggledFuture as LifesumImportReady;
      expect(toggled.selectedOperationCount, 6);
      expect(harness.targets.values, isEmpty);

      final confirmation = expectLater(
        bloc.stream,
        emitsInOrder(<Object>[
          isA<LifesumImportApplying>(),
          isA<LifesumImportSuccess>().having(
            (state) => state.addedCount,
            'added count',
            6,
          ),
        ]),
      );
      bloc.add(const ConfirmLifesumImportEvent());
      await confirmation;

      expect(harness.executorCreateCount, 1);
      expect(
        harness.targets.values.values.map((operation) => operation.kind),
        contains(LifesumImportOperationKind.estimatedWater),
      );
    },
  );

  test('rejects a stale profile before constructing the executor', () async {
    final readyFuture = bloc.stream.firstWhere(
      (state) => state is LifesumImportReady,
    );
    bloc.add(const ChooseLifesumArchiveEvent());
    await readyFuture;
    harness.database.simulateProfileSwitch(
      profileId: 'profile-a',
      generation: 2,
    );
    final errorFuture = bloc.stream.firstWhere(
      (state) => state is LifesumImportError,
    );

    bloc.add(const ConfirmLifesumImportEvent());
    final error = await errorFuture as LifesumImportError;

    expect(error.kind, LifesumImportErrorKind.profileChanged);
    expect(harness.executorCreateCount, 0);
    expect(harness.targets.values, isEmpty);
  });

  test('maps an unreadable selection to a value-free archive error', () async {
    await bloc.close();
    harness.dispose();
    harness = _Harness(invalidArchive: true);
    bloc = LifesumImportBloc(harness.coordinator);
    final errorFuture = bloc.stream.firstWhere(
      (state) => state is LifesumImportError,
    );

    bloc.add(const ChooseLifesumArchiveEvent());
    final error = await errorFuture as LifesumImportError;

    expect(error.kind, LifesumImportErrorKind.invalidArchive);
    expect(error.props, isNot(contains(harness.pickedPath)));
    expect(harness.executorCreateCount, 0);
  });
}

class _Harness {
  _Harness({bool cancelPicker = false, bool invalidArchive = false}) {
    directory = Directory.systemTemp.createTempSync('stable_lifesum_bloc_');
    final validArchive = writeSanitizedLifesumZip(directory).path;
    pickedPath = invalidArchive
        ? (File(
            '${directory.path}${Platform.pathSeparator}not-a-zip.txt',
          )..writeAsStringSync('synthetic invalid archive')).path
        : validArchive;
    database = FakeHiveDBProvider(
      activeProfileId: 'profile-a',
      activeProfileGeneration: 1,
    );
    journals = _MemoryJournalStore();
    targets = _MemoryTargetStore();
    final historyLoader = LifesumExistingHistoryLoader(
      activeProfileId: () => database.activeProfileId,
      activeProfileGeneration: () => database.activeProfileGeneration,
      loadIntakes: () async => const <IntakeEntity>[],
      loadActivities: () async => const <UserActivityEntity>[],
      loadWeights: () async => const <WeightLogEntity>[],
      loadBodyMeasurements: () async => const <BodyMeasurementLogEntity>[],
      loadTrackedDays: () async => const <TrackedDayEntity>[],
      loadWaterEntries: () async => const <WaterIntakeEntity>[],
      loadRecipes: () async => const <RecipeEntity>[],
    );
    coordinator = LifesumImportCoordinator(
      database: database,
      picker: picker = _TestPicker(cancelPicker ? null : pickedPath),
      historyLoader: historyLoader,
      loadSettings: () async => LifesumImportSettingsSnapshot(
        dayStartOffsetMinutes: 0,
        historicalGoals: LifesumHistoricalGoalSnapshot(
          calorieGoal: 2000,
          carbsGoal: 300,
          fatGoal: 55,
          proteinGoal: 75,
        ),
      ),
      createExecutor: () {
        executorCreateCount++;
        return LifesumImportExecutor(journals: journals, targets: targets);
      },
    );
  }

  late final Directory directory;
  late final String pickedPath;
  late final FakeHiveDBProvider database;
  late final _MemoryJournalStore journals;
  late final _MemoryTargetStore targets;
  late final LifesumImportCoordinator coordinator;
  late final _TestPicker picker;
  var executorCreateCount = 0;

  void dispose() => directory.deleteSync(recursive: true);
}

class _TestPicker implements LifesumArchivePicker, LifesumArchiveCleanup {
  _TestPicker(this.path);

  final String? path;
  int cleanupCount = 0;
  Completer<String?>? pending;
  Completer<void>? nextCleanup;

  @override
  Future<void> cleanupArchive() async {
    cleanupCount++;
    final completion = nextCleanup;
    nextCleanup = null;
    completion?.complete();
  }

  @override
  Future<String?> pickArchivePath() => pending?.future ?? Future.value(path);
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
    final current = values[operation.targetKey];
    if (current == null) return LifesumImportTargetProbe.absent;
    return current.operationId == operation.operationId
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
