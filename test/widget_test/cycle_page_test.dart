import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/notification_service.dart';
import 'package:opennutritracker/features/cycle/data/cycle_repository.dart';
import 'package:opennutritracker/features/cycle/domain/cycle_data.dart';
import 'package:opennutritracker/features/cycle/presentation/cycle_page.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/features/cycle/presentation/cycle_calendar.dart';
import 'package:opennutritracker/features/cycle/presentation/cycle_forms.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/diary_table_calendar.dart';
import 'package:table_calendar/table_calendar.dart';
import '../helpers/test_l10n.dart';

class _DB extends HiveDBProvider {
  Box<String> current;
  int generation = 0;
  _DB(this.current);
  @override
  Box<String> get cycleBox => current;
  @override
  int get activeProfileGeneration => generation;
  void switchTo(Box<String> box) {
    current = box;
    generation++;
    notifyListeners();
  }
}

class _Notifications extends NotificationService {
  DateTime? scheduled;
  @override
  Future<void> scheduleCycleReminder({
    required DateTime? when,
    required String title,
    required String body,
  }) async {
    scheduled = when;
  }
}

// Widget gestures run on a fake clock; keep disk I/O in the repository test.
class _EditorRepository extends CycleRepository {
  CycleData current;
  _EditorRepository(super.db, super.notifications, this.current);
  @override
  CycleData get data => current;
  @override
  Future<void> save(CycleData next, {required int generation}) async {
    if (generation != db.activeProfileGeneration) {
      throw StateError('Profile changed');
    }
    next.validate(today: DateTime.now());
    current = next;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _DB db;
  late CycleRepository repo;
  late _Notifications notifications;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('stable_cycle_');
    Hive.init(root.path);
    db = _DB(await Hive.openBox<String>('cycle'));
    notifications = _Notifications();
    repo = CycleRepository(db, notifications);
    locator.registerSingleton(repo);
    repo.useLabels(l10nEn);
    await repo.save(const CycleData(enabled: true), generation: 0);
  });
  tearDown(() async {
    await locator.reset();
    repo.dispose();
    db.dispose();
    await Hive.close();
    await root.delete(recursive: true);
  });

  test('profile changes isolate records and cancel the old reminder', () async {
    final now = DateTime.now();
    await repo.save(
      repo.data.copyWith(
        reminderEnabled: true,
        expectedOverride: DateTime(now.year, now.month, now.day + 10),
      ),
      generation: 0,
    );
    expect(notifications.scheduled, isNotNull);
    final other = await Hive.openBox<String>('other');
    db.switchTo(other);
    await Future<void>.delayed(Duration.zero);
    expect(repo.data.enabled, isFalse);
    expect(notifications.scheduled, isNull);
    await expectLater(
      repo.save(const CycleData(enabled: true), generation: 0),
      throwsStateError,
    );
    expect(other.isEmpty, isTrue);
  });

  Widget app(Widget child, {double scale = 1, bool dark = false}) =>
      MaterialApp(
        theme: buildAppTheme(dark ? AppPalette.dark : AppPalette.light),
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: child,
      );

  Finder day(DateTime date) => find.byKey(
    ValueKey('CellContent-${date.year}-${date.month}-${date.day}'),
  );

  Future<void> openEditor(WidgetTester tester, {PeriodRecord? record}) async {
    final data = repo.data;
    repo.dispose();
    await locator.unregister<CycleRepository>();
    repo = _EditorRepository(db, notifications, data);
    locator.registerSingleton<CycleRepository>(repo);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editPeriod(
                context,
                repo,
                past: record == null,
                record: record,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'past cycle selects a range, shows saved cycles, and saves dates',
    (tester) async {
      final now = DateTime.now();
      final first = DateTime(now.year, now.month - 1, 5);
      final last = DateTime(now.year, now.month - 1, 9);
      final existing = PeriodRecord(
        id: 'existing',
        start: DateTime(now.year, now.month - 1, 15),
        end: DateTime(now.year, now.month - 1, 18),
      );
      await tester.runAsync(
        () => repo.save(repo.data.copyWith(records: [existing]), generation: 0),
      );
      await openEditor(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, l10nEn.buttonSaveLabel),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      final calendar = tester.widget<TableCalendar<void>>(
        find.byType(TableCalendar<void>),
      );
      expect(calendar.startingDayOfWeek, StartingDayOfWeek.monday);
      // Every saved date is marked inside the calendar.
      expect(
        find.descendant(
          of: find.byType(TableCalendar<void>),
          matching: find.byType(CycleDateRing),
        ),
        findsNWidgets(4),
      );
      await tester.tap(day(first));
      await tester.pumpAndSettle();
      await tester.tap(day(last));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, l10nEn.buttonSaveLabel),
      );
      await tester.pumpAndSettle();
      expect(repo.data.records, hasLength(2));
      expect(repo.data.sorted.first.start, first);
      expect(repo.data.sorted.first.end, last);
      expect(repo.data.sorted.last.id, 'existing');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('overlap stays in editor and Cancel leaves saved dates intact', (
    tester,
  ) async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month - 1, 5);
    final record = PeriodRecord(
      id: 'existing',
      start: first,
      end: DateTime(first.year, first.month, 9),
    );
    await tester.runAsync(
      () => repo.save(repo.data.copyWith(records: [record]), generation: 0),
    );
    final before = repo.data.encode();
    await openEditor(tester);
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    await tester.tap(day(first));
    await tester.pumpAndSettle();
    await tester.tap(day(DateTime(first.year, first.month, 7)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10nEn.buttonSaveLabel));
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.cycleInvalid), findsOneWidget);
    expect(repo.data.encode(), before);
    await tester.tap(find.text(l10nEn.cycleCancel));
    await tester.pumpAndSettle();
    expect(repo.data.encode(), before);
  });

  testWidgets(
    'range can cross months and an existing cycle keeps its identity',
    (tester) async {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month - 1, 28);
      final record = PeriodRecord(id: 'existing', start: start, end: start);
      await tester.runAsync(
        () => repo.save(repo.data.copyWith(records: [record]), generation: 0),
      );
      await openEditor(tester, record: record);
      await tester.tap(day(start));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      final end = DateTime(now.year, now.month, 1);
      await tester.tap(day(end));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, l10nEn.buttonSaveLabel),
      );
      await tester.pumpAndSettle();
      expect(repo.data.records.single.id, 'existing');
      expect(repo.data.records.single.start, start);
      expect(repo.data.records.single.end, end);
    },
  );

  testWidgets(
    'one-day ranges save and ongoing cycles can receive an end date',
    (tester) async {
      final today = cycleDate(DateTime.now());
      final ongoing = PeriodRecord(id: 'ongoing', start: today);
      await tester.runAsync(
        () => repo.save(repo.data.copyWith(records: [ongoing]), generation: 0),
      );
      await openEditor(tester, record: ongoing);
      final toggle = find.byType(SwitchListTile);
      await tester.scrollUntilVisible(
        toggle,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.ensureVisible(day(today));
      await tester.tap(day(today));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, l10nEn.buttonSaveLabel),
      );
      await tester.pumpAndSettle();
      expect(repo.data.records.single.id, 'ongoing');
      expect(repo.data.records.single.start, today);
      expect(repo.data.records.single.end, today);
    },
  );

  testWidgets(
    'estimates validate lengths and save values without creating history',
    (tester) async {
      CycleData? result;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  result = await Navigator.of(context).push<CycleData>(
                    MaterialPageRoute(
                      builder: (_) => CycleSetupPage(data: repo.data),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '3');
      await tester.tap(
        find.widgetWithText(FilledButton, l10nEn.buttonSaveLabel),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.cycleInvalid), findsOneWidget);
      expect(result, isNull);
      await tester.enterText(find.byType(TextField).first, '30');
      await tester.tap(
        find.widgetWithText(FilledButton, l10nEn.buttonSaveLabel),
      );
      await tester.pumpAndSettle();
      expect(result!.guessedCycleDays, 30);
      expect(result!.guessedPeriodDays, 5);
      expect(result!.records, isEmpty);
      expect(repo.data.records, isEmpty);
    },
  );

  testWidgets('Diary rings surround dates and keep Monday first', (
    tester,
  ) async {
    final today = cycleDate(DateTime.now());
    await tester.runAsync(
      () => repo.save(
        repo.data.copyWith(
          records: [PeriodRecord(id: 'today', start: today, end: today)],
        ),
        generation: 0,
      ),
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          body: DiaryTableCalendar(
            onDateSelected: (_, _) {},
            calendarDurationDays: const Duration(days: 365),
            focusedDate: today,
            currentDate: today,
            selectedDate: today,
            trackedDaysMap: const {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TableCalendar>(
            find.byWidgetPredicate((widget) => widget is TableCalendar),
          )
          .startingDayOfWeek,
      StartingDayOfWeek.monday,
    );
    final rings = find.descendant(
      of: find.byWidgetPredicate((widget) => widget is TableCalendar),
      matching: find.byType(CycleDateRing),
    );
    expect(rings, findsWidgets);
    expect(tester.getSize(rings.first).width, greaterThan(30));
    await tester.tap(day(today));
    await tester.pumpAndSettle();
    expect(find.text(l10nEn.diaryLabel), findsOneWidget);
    expect(find.text(l10nEn.cycleLabel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.3, 1.6, 2.0]) {
    testWidgets('Cycle forms fit at 320px / $scale in both themes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final dark in [false, true]) {
        for (final screen in [
          CycleSetupPage(data: repo.data),
          PeriodEditorPage(data: repo.data, past: true),
          PeriodEditorPage(data: repo.data),
        ]) {
          await tester.pumpWidget(app(screen, scale: scale, dark: dark));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.drag(find.byType(ListView), const Offset(0, -500));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    });
  }

  for (final scale in [1.3, 1.6, 2.0]) {
    testWidgets('Cycle and Trends fit at 320px / $scale', (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(body: CyclePage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(l10nEn.cycleNoStart), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: SingleChildScrollView(child: CycleTrends()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
