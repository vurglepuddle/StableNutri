import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:opennutritracker/features/settings/presentation/lifesum_import_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../../fixture/lifesum_export_fixture.dart';
import '../../../helpers/fake_hive_db_provider.dart';

void main() {
  late _Harness harness;
  late LifesumImportBloc bloc;
  var refreshCount = 0;

  setUp(() {
    harness = _Harness();
    bloc = LifesumImportBloc(harness.coordinator);
    refreshCount = 0;
  });

  tearDown(() async {
    await bloc.close();
    harness.dispose();
  });

  Future<void> pumpScreen(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          S.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: LifesumImportScreen(bloc: bloc, onImported: () => refreshCount++),
      ),
    );
  }

  Future<void> loadReview(WidgetTester tester) async {
    final chooseButton = find.byKey(const ValueKey('lifesum-choose-archive'));
    final readyFuture = bloc.stream.firstWhere(
      (state) => state is LifesumImportReady,
    );
    await tester.ensureVisible(chooseButton);
    await tester.pumpAndSettle();
    await tester.tap(chooseButton);
    await tester.pump();
    await tester.runAsync(() => readyFuture);
    await tester.pump();
    expect(bloc.state, isA<LifesumImportReady>());
    expect(find.text('Review before importing'), findsOneWidget);
  }

  testWidgets('keeps preview read-only and water opt-in until final confirm', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Bring your history'), findsOneWidget);
    expect(find.textContaining('not uploaded'), findsOneWidget);
    expect(harness.targets.values, isEmpty);
    await loadReview(tester);

    expect(find.text('Food diary'), findsOneWidget);
    expect(find.text('Activities'), findsOneWidget);
    expect(find.text('Weight history'), findsOneWidget);
    expect(find.text('Body measurements'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Favorites'), 250);
    expect(find.text('Recipes'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Not imported'), findsNWidgets(2));
    expect(harness.targets.values, isEmpty);

    final waterCard = find.byKey(const ValueKey('lifesum-water-category'));
    await tester.scrollUntilVisible(waterCard, 250);
    final waterSwitch = find.descendant(
      of: waterCard,
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(waterSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(waterSwitch).value, isFalse);
    final waterSelectedFuture = bloc.stream.firstWhere(
      (state) =>
          state is LifesumImportReady && state.selection.includeEstimatedWater,
    );
    await tester.tap(waterSwitch);
    await tester.pump();
    await tester.runAsync(() => waterSelectedFuture);
    await tester.pump();
    expect(
      (bloc.state as LifesumImportReady).selection.includeEstimatedWater,
      isTrue,
    );
    expect(tester.widget<Switch>(waterSwitch).value, isTrue);
    expect(harness.targets.values, isEmpty);

    final importButton = find.byKey(const ValueKey('lifesum-review-import'));
    await tester.scrollUntilVisible(importButton, 250);
    await tester.tap(importButton);
    await tester.pumpAndSettle();
    expect(find.text('Import selected history?'), findsOneWidget);
    expect(harness.targets.values, isEmpty);

    await tester.tap(find.byKey(const ValueKey('lifesum-cancel-import')));
    await tester.pumpAndSettle();
    expect(bloc.state, isA<LifesumImportReady>());
    expect(find.text('Import selected history?'), findsNothing);
    expect(importButton, findsOneWidget);
    expect(harness.targets.values, isEmpty);

    await tester.tap(importButton);
    await tester.pumpAndSettle();
    final successFuture = bloc.stream.firstWhere(
      (state) => state is LifesumImportSuccess,
    );
    await tester.tap(find.byKey(const ValueKey('lifesum-confirm-import')));
    await tester.pump();
    await tester.runAsync(() => successFuture);
    await tester.pump();

    expect(find.text('History imported'), findsOneWidget);
    expect(find.textContaining('6 records added'), findsOneWidget);
    expect(refreshCount, 1);
    expect(harness.targets.values, hasLength(6));
  });

  testWidgets('review remains usable at 320 px and 1.6x text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpScreen(tester, textScale: 1.6);
    await loadReview(tester);

    final importButton = find.byKey(const ValueKey('lifesum-review-import'));
    await tester.scrollUntilVisible(importButton, 300);
    await tester.pumpAndSettle();
    expect(importButton, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Harness {
  _Harness() {
    directory = Directory.systemTemp.createTempSync('stable_lifesum_screen_');
    final archive = writeSanitizedLifesumZip(directory);
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
      picker: _TestPicker(archive.path),
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
      createExecutor: () =>
          LifesumImportExecutor(journals: journals, targets: targets),
    );
  }

  late final Directory directory;
  late final FakeHiveDBProvider database;
  late final _MemoryJournalStore journals;
  late final _MemoryTargetStore targets;
  late final LifesumImportCoordinator coordinator;

  void dispose() => directory.deleteSync(recursive: true);
}

class _TestPicker implements LifesumArchivePicker {
  const _TestPicker(this.path);

  final String path;

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
