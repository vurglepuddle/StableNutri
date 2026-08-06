import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/features/home/presentation/widgets/quick_weight_widget.dart';
import 'package:opennutritracker/generated/l10n.dart';

Widget _wrap(Widget child, {TextScaler textScaler = TextScaler.noScaling}) {
  return MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.delegate.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('QuickWeightWidget corridor summary', () {
    testWidgets('shows the configured corridor and neutral status', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const QuickWeightWidget(
            weightKg: 72,
            bodyWeightUnit: BodyWeightUnit.kg,
            weightCorridorLowerKg: 70,
            weightCorridorUpperKg: 75,
          ),
        ),
      );

      expect(
        find.byKey(const Key('homeWeightCorridorSummary')),
        findsOneWidget,
      );
      expect(find.text('70–75 kg · within weight corridor'), findsOneWidget);
    });

    testWidgets('hides an unset point fallback', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const QuickWeightWidget(
            weightKg: 72,
            bodyWeightUnit: BodyWeightUnit.kg,
            weightCorridorLowerKg: 72,
            weightCorridorUpperKg: 72,
          ),
        ),
      );

      expect(find.text('72 kg'), findsOneWidget);
      expect(find.byKey(const Key('homeWeightCorridorSummary')), findsNothing);
    });

    testWidgets('wraps a stone corridor at large text without overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          const QuickWeightWidget(
            weightKg: 72,
            bodyWeightUnit: BodyWeightUnit.st,
            weightCorridorLowerKg: 70,
            weightCorridorUpperKg: 75,
          ),
          textScaler: const TextScaler.linear(1.8),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('homeWeightCorridorSummary')),
        findsOneWidget,
      );
    });
  });
}
