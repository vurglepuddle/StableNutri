import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/health/health_connect_service.dart';
import 'package:opennutritracker/core/data/health/health_steps_sync.dart';
import 'package:opennutritracker/core/data/repository/daily_steps_repository.dart';
import 'package:opennutritracker/core/domain/entity/daily_steps.dart';
import 'package:opennutritracker/core/presentation/widgets/activity_vertial_list.dart';
import 'package:opennutritracker/core/presentation/widgets/daily_steps_card.dart';
import 'package:opennutritracker/features/settings/presentation/health_connect_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';

class MemorySteps implements DailyStepsRepository {
  bool enabled = false;
  final rows = <DailySteps>[];
  @override
  bool get autoImportEnabled => enabled;
  @override
  List<DailySteps> all() => rows.toList();
  @override
  DailyStepsImport beginImport() => MemoryTarget(this);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryTarget implements DailyStepsImport {
  final MemorySteps repository;
  MemoryTarget(this.repository);
  @override
  void requireCurrentProfile() {}
  @override
  Future<void> setAutoImport(bool enabled) async {
    repository.enabled = enabled;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeStepAccess extends HealthConnectService {
  bool granted = true;
  int requests = 0;
  @override
  Future<String> status() async => 'available';
  @override
  Future<bool> requestReadPermissions() async {
    requests++;
    return granted;
  }
}

class FakeStepSync implements HealthStepsSync {
  @override
  final MemorySteps repository;
  int reads = 0;
  FakeStepSync(this.repository);
  @override
  Future<StepSyncResult> sync({bool force = false}) async {
    reads++;
    repository.rows.clear();
    repository.rows.add(
      DailySteps(
        day: DateTime(2026, 9, 12),
        steps: 7654,
        readAt: DateTime(2026, 9, 12, 18),
        offsetMinutes: 0,
      ),
    );
    return StepSyncResult.updated;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MemorySteps repository;
  late FakeStepAccess access;
  late FakeStepSync sync;

  setUp(() {
    repository = MemorySteps();
    access = FakeStepAccess();
    sync = FakeStepSync(repository);
  });

  Widget app(Widget child) => MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    home: child,
  );

  Future<void> showScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      app(
        HealthConnectScreen(
          repository: repository,
          service: access,
          sync: sync,
          profileName: 'Alex',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'explicitly enabling steps activates import only for this profile',
    (tester) async {
      await showScreen(tester);
      expect(access.requests, 0);
      expect(sync.reads, 0);
      expect(find.text('Import into Alex'), findsOneWidget);
      await tester.ensureVisible(find.text('Enable step import'));
      await tester.tap(find.text('Enable step import'));
      await tester.pumpAndSettle();
      expect(access.requests, 1);
      expect(repository.enabled, isTrue);
      expect(sync.reads, 1);
      expect(find.text('7,654 steps'), findsOneWidget);
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(repository.enabled, isFalse);
      expect(repository.rows.single.steps, 7654);
    },
  );

  testWidgets('denied step permission leaves automatic import disabled', (
    tester,
  ) async {
    access.granted = false;
    await showScreen(tester);
    await tester.ensureVisible(find.text('Enable step import'));
    await tester.tap(find.text('Enable step import'));
    await tester.pumpAndSettle();
    expect(repository.enabled, isFalse);
    expect(sync.reads, 0);
  });

  for (final scale in [1.3, 1.6, 2.0]) {
    testWidgets(
      'Activity shows steps at 320px and ${scale}x text without kcal',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await tester.pumpWidget(
          app(
            Scaffold(
              body: ListView(
                children: [
                  ActivityVerticalList(
                    day: DateTime(2026, 9, 12),
                    title: 'Activity',
                    userActivityList: const [],
                    onItemLongPressedCallback: (_, _) {},
                    dailySteps: DailySteps(
                      day: DateTime(2026, 9, 12),
                      steps: 120000,
                      readAt: DateTime(2026, 9, 12, 18),
                      offsetMinutes: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DailyStepsCard), findsOneWidget);
        expect(find.text('Walking · 120,000 steps'), findsOneWidget);
        expect(find.textContaining('kcal'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('settings remain scrollable with large text on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await showScreen(tester);
    await tester.scrollUntilVisible(find.text('Enable step import'), 250);
    await tester.tap(find.text('Enable step import'));
    await tester.pumpAndSettle();
    expect(repository.enabled, isTrue);
    expect(tester.takeException(), isNull);
  });
}
