import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_body_measurement_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_body_measurement_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/features/measurements/presentation/widgets/measurement_log_sheet.dart';
import 'package:opennutritracker/generated/l10n.dart';

class _FakeAddWeight implements AddWeightLogUsecase {
  final entries = <WeightLogEntity>[];

  @override
  Future<void> addEntry(WeightLogEntity entry) async => entries.add(entry);
}

class _FakeGetWeight implements GetWeightLogUsecase {
  WeightLogEntity? entry;

  @override
  Future<WeightLogEntity?> getEntry(DateTime date) async => entry;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAddMeasurement implements AddBodyMeasurementLogUsecase {
  final entries = <BodyMeasurementLogEntity>[];

  @override
  Future<void> addEntry(BodyMeasurementLogEntity entry) async =>
      entries.add(entry);
}

class _FakeGetMeasurement implements GetBodyMeasurementLogUsecase {
  BodyMeasurementLogEntity? entry;

  @override
  Future<BodyMeasurementLogEntity?> getEntry(DateTime date) async => entry;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app({
  required _FakeAddWeight addWeight,
  required _FakeGetWeight getWeight,
  required _FakeAddMeasurement addMeasurement,
  required _FakeGetMeasurement getMeasurement,
  bool imperial = false,
  double textScale = 1,
}) {
  return MaterialApp(
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.delegate.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: MeasurementLogSheet(
        currentWeightKg: 68.6,
        bodyWeightUnit: BodyWeightUnit.kg,
        usesImperialLengthUnits: imperial,
        addWeightUsecase: addWeight,
        getWeightUsecase: getWeight,
        addMeasurementUsecase: addMeasurement,
        getMeasurementUsecase: getMeasurement,
      ),
    ),
  );
}

void main() {
  testWidgets('saves weight and a partial metric snapshot', (tester) async {
    final addWeight = _FakeAddWeight();
    final addMeasurement = _FakeAddMeasurement();
    await tester.pumpWidget(
      _app(
        addWeight: addWeight,
        getWeight: _FakeGetWeight(),
        addMeasurement: addMeasurement,
        getMeasurement: _FakeGetMeasurement(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('measurement-waist-input')),
      '78.2',
    );
    await tester.enterText(
      find.byKey(const Key('measurement-note-input')),
      'Feeling stronger',
    );
    await tester.ensureVisible(
      find.byKey(const Key('measurement-save-button')),
    );
    await tester.tap(find.byKey(const Key('measurement-save-button')));
    await tester.pumpAndSettle();

    expect(addWeight.entries, hasLength(1));
    expect(addWeight.entries.single.weightKg, 68.6);
    expect(addMeasurement.entries, hasLength(1));
    expect(addMeasurement.entries.single.waistCm, 78.2);
    expect(addMeasurement.entries.single.hipsCm, isNull);
    expect(addMeasurement.entries.single.note, 'Feeling stronger');
  });

  testWidgets('converts imperial length input to centimetres', (tester) async {
    final addMeasurement = _FakeAddMeasurement();
    await tester.pumpWidget(
      _app(
        addWeight: _FakeAddWeight(),
        getWeight: _FakeGetWeight(),
        addMeasurement: addMeasurement,
        getMeasurement: _FakeGetMeasurement(),
        imperial: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('measurement-waist-input')),
      '31.5',
    );
    await tester.ensureVisible(
      find.byKey(const Key('measurement-save-button')),
    );
    await tester.tap(find.byKey(const Key('measurement-save-button')));
    await tester.pumpAndSettle();

    expect(addMeasurement.entries.single.waistCm, closeTo(80.01, 0.001));
  });

  testWidgets('rejects body fat above 100 percent', (tester) async {
    final addMeasurement = _FakeAddMeasurement();
    await tester.pumpWidget(
      _app(
        addWeight: _FakeAddWeight(),
        getWeight: _FakeGetWeight(),
        addMeasurement: addMeasurement,
        getMeasurement: _FakeGetMeasurement(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('measurement-bodyFat-input')),
      '101',
    );
    await tester.ensureVisible(
      find.byKey(const Key('measurement-save-button')),
    );
    await tester.tap(find.byKey(const Key('measurement-save-button')));
    await tester.pump();

    expect(find.byKey(const Key('measurementFormError')), findsOneWidget);
    expect(addMeasurement.entries, isEmpty);
  });

  testWidgets('remains scrollable on a narrow screen with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(
        addWeight: _FakeAddWeight(),
        getWeight: _FakeGetWeight(),
        addMeasurement: _FakeAddMeasurement(),
        getMeasurement: _FakeGetMeasurement(),
        textScale: 1.6,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Log measurements'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('measurement-save-button')),
    );
    expect(tester.takeException(), isNull);
  });
}
