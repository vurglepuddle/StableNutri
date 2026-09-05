import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/day_water_widget.dart';
import 'package:opennutritracker/generated/l10n.dart';

void main() {
  testWidgets(
    'historical water shows exact totals and estimated provenance without editing',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
            body: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(1.6),
                alwaysUse24HourFormat: true,
              ),
              child: SingleChildScrollView(
                child: DayWaterWidget(
                  entries: [
                    WaterIntakeEntity(
                      id: 'manual',
                      dateTime: DateTime(2024, 2, 1, 12, 30),
                      amountMl: 350,
                    ),
                    WaterIntakeEntity(
                      id: 'lifesum-estimated-water-example',
                      dateTime: DateTime(2024, 2, 1, 4),
                      amountMl: 2000,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2.4 l'), findsOneWidget);
      await tester.tap(find.byKey(const Key('diary-water')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Estimated water history'), findsOneWidget);
      expect(find.text('2000 ml'), findsOneWidget);
      expect(find.text('350 ml'), findsOneWidget);
      expect(find.text('12:30'), findsOneWidget);
      expect(find.text('04:00'), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    },
  );
}
