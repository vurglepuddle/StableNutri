import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/scanner/data/product_not_found_exception.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/search_product_by_barcode_usecase.dart';
import 'package:opennutritracker/features/scanner/presentation/scanner_bloc.dart';
import 'package:opennutritracker/features/scanner/presentation/widgets/barcode_lookup_progress.dart';
import 'package:opennutritracker/generated/l10n.dart';

import '../../helpers/test_l10n.dart';

/// A lookup crossing slow databases used to show a bare spinner, which read
/// as a hang. It now says which source it is asking, and reassures after a
/// few seconds.
void main() {
  group('BarcodeLookupProgress', () {
    Future<void> pump(WidgetTester tester, BarcodeLookupStage stage) =>
        tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [S.delegate],
            home: Scaffold(body: BarcodeLookupProgress(stage: stage)),
          ),
        );

    testWidgets('names the source being asked', (tester) async {
      await pump(tester, BarcodeLookupStage.openFoodFacts);
      expect(find.text(l10nEn.scannerLookupOpenFoodFacts), findsOneWidget);

      await pump(tester, BarcodeLookupStage.metro);
      expect(find.text(l10nEn.scannerLookupMetro), findsOneWidget);
    });

    testWidgets('reassures once the wait gets long, not before', (
      tester,
    ) async {
      await pump(tester, BarcodeLookupStage.local);
      expect(find.text(l10nEn.scannerLookupStarting), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      expect(find.text(l10nEn.scannerLookupSlow), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text(l10nEn.scannerLookupSlow), findsOneWidget);
    });

    testWidgets('the reassurance survives a change of source', (tester) async {
      await pump(tester, BarcodeLookupStage.openFoodFacts);
      await tester.pump(BarcodeLookupProgress.slowAfter);
      await pump(tester, BarcodeLookupStage.metro);

      expect(find.text(l10nEn.scannerLookupMetro), findsOneWidget);
      expect(find.text(l10nEn.scannerLookupSlow), findsOneWidget);
    });
  });

  test('ScannerBloc passes each stage on while loading', () async {
    final bloc = ScannerBloc(_StagedNotFound(), _Config());
    addTearDown(bloc.close);

    final states = <ScannerState>[];
    final subscription = bloc.stream.listen(states.add);
    bloc.add(const ScannerLoadProductEvent(barcode: '4600000000000'));
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(
      states.whereType<ScannerLoadingState>().map((s) => s.stage).toList(),
      [
        BarcodeLookupStage.local,
        BarcodeLookupStage.openFoodFacts,
        BarcodeLookupStage.metro,
      ],
    );
    expect(states.last, isA<ScannerFailedState>());
  });
}

class _StagedNotFound implements SearchProductByBarcodeUseCase {
  @override
  Future<MealEntity> searchProductByBarcode(
    String barcode, {
    ValueChanged<BarcodeLookupStage>? onStage,
  }) async {
    onStage?.call(BarcodeLookupStage.openFoodFacts);
    onStage?.call(BarcodeLookupStage.metro);
    throw ProductNotFoundException();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}

class _Config implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      ConfigEntity(true, true, false, AppThemeEntity.system);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected call: ${invocation.memberName}');
}
