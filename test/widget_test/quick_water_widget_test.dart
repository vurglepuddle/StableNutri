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
    pending.complete();
    await tester.pumpAndSettle();
  });
}
