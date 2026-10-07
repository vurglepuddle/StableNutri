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
