import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/home/presentation/widgets/water_card.dart';
import 'package:opennutritracker/generated/l10n.dart';

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
  localizationsDelegates: const [
    S.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: S.delegate.supportedLocales,
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: child,
    ),
  ),
);

/// The painted water level of one cup. Reading the painter rather than a clip
/// rectangle keeps the assertion on the thing the user actually sees.
double _fill(WidgetTester tester, int index) {
  final painters = tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byKey(ValueKey('water-cup-$index')),
          matching: find.byType(CustomPaint),
        ),
      )
      .map((paint) => paint.painter)
      .where((painter) => painter.runtimeType.toString() == '_CupPainter');
  expect(painters, hasLength(1), reason: 'one cup painter for cup $index');
  return (painters.first as dynamic).fill as double;
}

void main() {
  testWidgets('one tap fills exactly one cup, even on a non-divisible goal', (
    tester,
  ) async {
    var total = 0;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => WaterCard(
            waterMlToday: total,
            waterGoalMl: 2000,
            amountMl: 300,
            onAdd: (amount) async => setState(() => total += amount),
            onRemove: (amount) async => setState(() => total -= amount),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var tap = 1; tap <= 5; tap++) {
      await tester.tap(find.byKey(ValueKey('water-cup-${tap - 1}')));
      await tester.pumpAndSettle();
      expect(total, tap * 300);
      for (var index = 0; index <= tap; index++) {
        expect(_fill(tester, index), index < tap ? 1.0 : 0.0);
      }
    }
  });

  testWidgets('tapping a full cup removes exactly one cup', (tester) async {
    var total = 1000;
    final removed = <int>[];
    final added = <int>[];
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => WaterCard(
            waterMlToday: total,
            waterGoalMl: 2000,
            amountMl: 250,
            onAdd: (amount) async {
              added.add(amount);
              setState(() => total += amount);
            },
            onRemove: (amount) async {
              removed.add(amount);
              setState(() => total -= amount);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Cups 0-3 are full, cup 4 is the empty frontier.
    await tester.tap(find.byKey(const ValueKey('water-cup-3')));
    await tester.pumpAndSettle();
    expect(removed, [250]);
    expect(added, isEmpty);
    expect(total, 750);
    expect(_fill(tester, 2), 1.0);
    expect(_fill(tester, 3), 0.0);
    // The frontier cup adds rather than removes, matching the "+" it carries.
    await tester.tap(find.byKey(const ValueKey('water-cup-3')));
    await tester.pumpAndSettle();
    expect(added, [250]);
    expect(total, 1000);
    // An empty cup past the frontier still adds.
    await tester.tap(find.byKey(const ValueKey('water-cup-6')));
    await tester.pumpAndSettle();
    expect(added, [250, 250]);
    expect(total, 1250);
  });

  testWidgets('a part-filled cup adds, and removal never runs it negative', (
    tester,
  ) async {
    var total = 625;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => WaterCard(
            waterMlToday: total,
            waterGoalMl: 2000,
            amountMl: 250,
            onAdd: (amount) async => setState(() => total += amount),
            onRemove: (amount) async =>
                setState(() => total = (total - amount).clamp(0, total)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_fill(tester, 0), 1.0);
    expect(_fill(tester, 1), 1.0);
    expect(_fill(tester, 2), 0.5);
    expect(_fill(tester, 3), 0.0);
    await tester.tap(find.byKey(const ValueKey('water-cup-2')));
    await tester.pumpAndSettle();
    expect(total, 875);
    await tester.tap(find.byKey(const ValueKey('water-cup-0')));
    await tester.pumpAndSettle();
    expect(total, 625);
  });

  testWidgets('the level animates rather than snapping', (tester) async {
    var total = 0;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => WaterCard(
            waterMlToday: total,
            waterGoalMl: 2000,
            amountMl: 250,
            onAdd: (amount) async => setState(() => total += amount),
            onRemove: (amount) async => setState(() => total -= amount),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('water-cup-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final midway = _fill(tester, 0);
    expect(midway, greaterThan(0.0));
    expect(midway, lessThan(1.0));
    // Every animation here is finite, so the frame scheduler quiets down.
    await tester.pumpAndSettle();
    expect(_fill(tester, 0), 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate in-flight taps are ignored', (tester) async {
    final amounts = <int>[];
    final pending = Completer<void>();
    await tester.pumpWidget(
      _app(
        WaterCard(
          waterMlToday: 500,
          waterGoalMl: 2000,
          amountMl: 400,
          onAdd: (amount) {
            amounts.add(amount);
            return pending.future;
          },
          onRemove: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('water-cup-3')));
    await tester.pump();
    expect(amounts, [400]);
    await tester.tap(find.byKey(const ValueKey('water-cup-3')));
    await tester.pump();
    expect(amounts, [400]);
    pending.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('water-cup-3')));
    await tester.pumpAndSettle();
    expect(amounts, [400, 400]);
  });

  testWidgets('the total reads in litres and marks the goal once reached', (
    tester,
  ) async {
    Future<void> show(int total) async {
      await tester.pumpWidget(
        _app(
          WaterCard(
            waterMlToday: total,
            waterGoalMl: 2000,
            amountMl: 250,
            onAdd: (_) async {},
            onRemove: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(1200);
    expect(find.text('Water'), findsOneWidget);
    expect(find.textContaining('1'), findsWidgets);
    expect(find.textContaining('ml'), findsNothing);
    expect(find.textContaining('/ 2 l)'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    await show(2000);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    // Past the goal there is always one more cup to pour into.
    await show(2000);
    expect(find.byKey(const ValueKey('water-cup-8')), findsOneWidget);
    expect(_fill(tester, 8), 0.0);
  });

  testWidgets('the menu logs, undoes and opens the goal without adding water', (
    tester,
  ) async {
    var edits = 0;
    var goals = 0;
    var undos = 0;
    final amounts = <int>[];
    await tester.pumpWidget(
      _app(
        WaterCard(
          waterMlToday: 500,
          waterGoalMl: 2000,
          amountMl: 250,
          onAdd: (amount) async => amounts.add(amount),
          onRemove: (amount) async => amounts.add(-amount),
          onEdit: () => edits++,
          onEditGoal: () => goals++,
          onUndo: () async {
            undos++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> pick(String label) async {
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await pick('Log water intake');
    await pick('Undo last');
    await pick('Daily water goal');
    expect(edits, 1);
    expect(undos, 1);
    expect(goals, 1);
    expect(amounts, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a narrow screen at 1.6x text scrolls instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        WaterCard(
          waterMlToday: 625,
          waterGoalMl: 2000,
          amountMl: 250,
          onAdd: (_) async {},
          onRemove: (_) async {},
        ),
        textScale: 1.6,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final first = tester.getRect(find.byKey(const ValueKey('water-cup-0')));
    expect(first.size.width, greaterThanOrEqualTo(40));
    expect(first.size.height, greaterThanOrEqualTo(48));
    expect(first.left, greaterThanOrEqualTo(0));
    expect(find.byType(ListView), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    final last = tester.getRect(find.byKey(const ValueKey('water-cup-7')));
    expect(last.right, lessThanOrEqualTo(320));
    expect(last.bottom, first.bottom);
  });

  testWidgets('a wide card lays the cups out in a single non-scrolling row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        WaterCard(
          waterMlToday: 0,
          waterGoalMl: 2000,
          amountMl: 250,
          onAdd: (_) async {},
          onRemove: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsNothing);
    final first = tester.getRect(find.byKey(const ValueKey('water-cup-0')));
    final last = tester.getRect(find.byKey(const ValueKey('water-cup-7')));
    expect(first.top, last.top);
    expect(last.right, lessThanOrEqualTo(800));
    expect(first.size.width, greaterThanOrEqualTo(40));
  });
}
