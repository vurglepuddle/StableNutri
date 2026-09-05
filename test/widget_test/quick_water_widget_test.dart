import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/home/presentation/widgets/quick_water_widget.dart';
import 'package:opennutritracker/generated/l10n.dart';

void main() {
  testWidgets('water adds with one tap and edit does not add a drink', (
    tester,
  ) async {
    final amounts = <int>[];
    var edits = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: Scaffold(
          body: QuickWaterWidget(
            waterMlToday: 500,
            waterGoalMl: 2000,
            amountMl: 400,
            onAdd: (amount) {
              amounts.add(amount);
              return pending.future;
            },
            onEdit: () => edits++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    expect(edits, 1);
    expect(amounts, isEmpty);
    await tester.tap(find.byType(ActionChip));
    await tester.pump();
    expect(amounts, [400]);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byType(ActionChip));
    expect(amounts, [400]);
    await tester.tap(find.byKey(const ValueKey('water-glass-0')));
    expect(amounts, [400]);
    pending.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('water-glass-0')));
    await tester.pumpAndSettle();
    expect(amounts, [400, 400]);
  });

  testWidgets(
    'glass fill follows recorded totals, including partial drinks and undo',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> show(int total) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [S.delegate],
            supportedLocales: S.delegate.supportedLocales,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: QuickWaterWidget(
                    waterMlToday: total,
                    waterGoalMl: 2000,
                    amountMl: 250,
                    onAdd: (_) async {},
                    onEdit: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      double fill(int index) {
        final clip = tester.widget<ClipRect>(
          find.descendant(
            of: find.byKey(ValueKey('water-glass-$index')),
            matching: find.byType(ClipRect),
          ),
        );
        return clip.clipper!.getClip(const Size(28, 28)).height / 28;
      }

      await show(625);
      expect(fill(0), 1);
      expect(fill(1), 1);
      expect(fill(2), .5);
      expect(fill(3), 0);
      final first = tester.getRect(find.byKey(const ValueKey('water-glass-0')));
      final last = tester.getRect(find.byKey(const ValueKey('water-glass-5')));
      expect(first.size.width, greaterThanOrEqualTo(48));
      expect(first.size.height, greaterThanOrEqualTo(48));
      expect(last.bottom, first.bottom);
      expect(tester.getSize(find.byType(ListView)).height, 48);
      await show(225);
      expect(fill(0), closeTo(.9, .0001));
      expect(fill(1), 0);
      await show(2400);
      expect(fill(5), 1);
      expect(find.textContaining('2400'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(fill(7), 1);
      expect(
        tester.getRect(find.byKey(const ValueKey('water-glass-7'))).right,
        lessThanOrEqualTo(304),
      );
    },
  );

  testWidgets(
    'one tap fills exactly one selected-size cup even when the goal is not divisible',
    (tester) async {
      var total = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.delegate.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => QuickWaterWidget(
                waterMlToday: total,
                waterGoalMl: 2000,
                amountMl: 300,
                onAdd: (amount) async {
                  setState(() => total += amount);
                },
                onEdit: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var tap = 1; tap <= 5; tap++) {
        await tester.tap(find.byKey(const ValueKey('water-glass-0')));
        await tester.pumpAndSettle();
        expect(total, tap * 300);
        for (var index = 0; index <= tap; index++) {
          final clip = tester.widget<ClipRect>(
            find.descendant(
              of: find.byKey(ValueKey('water-glass-$index')),
              matching: find.byType(ClipRect),
            ),
          );
          expect(
            clip.clipper!.getClip(const Size(28, 28)).height,
            index < tap ? 28 : 0,
          );
        }
      }
    },
  );
}
