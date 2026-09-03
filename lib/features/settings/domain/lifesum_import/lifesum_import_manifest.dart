import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_preview.dart';

enum LifesumImportOperationKind {
  weight,
  bodyMeasurement,
  trackedDay,
  intake,
  activity,
  estimatedWater,
}

/// One deterministic mutation target and its in-memory payload.
///
/// Payloads are deliberately absent from the persisted journal. Only the
/// opaque [operationId] is needed to resume or roll back a confirmed import.
sealed class LifesumImportOperation {
  const LifesumImportOperation({
    required this.kind,
    required this.operationId,
    required this.targetKey,
    required this.logicalDay,
    required this.payloadDigest,
  });

  final LifesumImportOperationKind kind;
  final String operationId;
  final String targetKey;
  final DateTime logicalDay;
  final String payloadDigest;

  /// Returns true only when [entity] is the exact payload this operation
  /// would persist at its deterministic target. The executor can therefore
  /// distinguish its own crash-recovered write from a record edited by the
  /// user under the same ID or calendar-day key.
  bool matchesTargetEntity(Object entity);
}

class LifesumWeightImportOperation extends LifesumImportOperation {
  LifesumWeightImportOperation(this.entry)
    : super(
        kind: LifesumImportOperationKind.weight,
        operationId:
            'weight:${_dateSlug(entry.date)}:${_weightPayloadDigest(entry)}',
        targetKey: 'weight:${_dateSlug(entry.date)}',
        logicalDay: _calendarDay(entry.date),
        payloadDigest: _weightPayloadDigest(entry),
      );

  final WeightLogEntity entry;

  @override
  bool matchesTargetEntity(Object entity) =>
      entity is WeightLogEntity &&
      _dateSlug(entity.date) == _dateSlug(entry.date) &&
      _weightPayloadDigest(entity) == payloadDigest;
}

class LifesumBodyMeasurementImportOperation extends LifesumImportOperation {
  LifesumBodyMeasurementImportOperation(this.entry)
    : super(
        kind: LifesumImportOperationKind.bodyMeasurement,
        operationId:
            'body-measurement:${_dateSlug(entry.date)}:'
            '${_bodyMeasurementPayloadDigest(entry)}',
        targetKey: 'body-measurement:${_dateSlug(entry.date)}',
        logicalDay: _calendarDay(entry.date),
        payloadDigest: _bodyMeasurementPayloadDigest(entry),
      );

  final BodyMeasurementLogEntity entry;

  @override
  bool matchesTargetEntity(Object entity) =>
      entity is BodyMeasurementLogEntity &&
      _dateSlug(entity.date) == _dateSlug(entry.date) &&
      _bodyMeasurementPayloadDigest(entity) == payloadDigest;
}

class LifesumTrackedDayImportOperation extends LifesumImportOperation {
  LifesumTrackedDayImportOperation(this.entry)
    : super(
        kind: LifesumImportOperationKind.trackedDay,
        operationId:
            'tracked-day:${_dateSlug(entry.day)}:'
            '${_trackedDayPayloadDigest(entry)}',
        targetKey: 'tracked-day:${_dateSlug(entry.day)}',
        logicalDay: _calendarDay(entry.day),
        payloadDigest: _trackedDayPayloadDigest(entry),
      );

  final TrackedDayEntity entry;

  @override
  bool matchesTargetEntity(Object entity) =>
      entity is TrackedDayEntity &&
      _dateSlug(entity.day) == _dateSlug(entry.day) &&
      _trackedDayPayloadDigest(entity) == payloadDigest;
}

class LifesumIntakeImportOperation extends LifesumImportOperation {
  LifesumIntakeImportOperation(this.entry, {required int dayStartOffsetMinutes})
    : super(
        kind: LifesumImportOperationKind.intake,
        operationId: 'intake:${entry.id}:${_intakePayloadDigest(entry)}',
        targetKey: 'intake:${entry.id}',
        logicalDay: DayBoundaryCalc.logicalDayOfMinutes(
          entry.dateTime,
          dayStartOffsetMinutes,
        ),
        payloadDigest: _intakePayloadDigest(entry),
      );

  final IntakeEntity entry;

  @override
  bool matchesTargetEntity(Object entity) =>
      entity is IntakeEntity &&
      entity.id == entry.id &&
      _intakePayloadDigest(entity) == payloadDigest;
}

class LifesumActivityImportOperation extends LifesumImportOperation {
  LifesumActivityImportOperation(
    this.entry, {
    required int dayStartOffsetMinutes,
  }) : super(
         kind: LifesumImportOperationKind.activity,
         operationId: 'activity:${entry.id}:${_activityPayloadDigest(entry)}',
         targetKey: 'activity:${entry.id}',
         logicalDay: DayBoundaryCalc.logicalDayOfMinutes(
           entry.date,
           dayStartOffsetMinutes,
         ),
         payloadDigest: _activityPayloadDigest(entry),
       );

  final UserActivityEntity entry;

  @override
  bool matchesTargetEntity(Object entity) =>
      entity is UserActivityEntity &&
      entity.id == entry.id &&
      _activityPayloadDigest(entity) == payloadDigest;
}

class LifesumEstimatedWaterImportOperation extends LifesumImportOperation {
  LifesumEstimatedWaterImportOperation(
    this.entry, {
    required int dayStartOffsetMinutes,
  }) : super(
         kind: LifesumImportOperationKind.estimatedWater,
         operationId:
             'estimated-water:${entry.id}:${_waterPayloadDigest(entry)}',
         targetKey: 'estimated-water:${entry.id}',
         logicalDay: DayBoundaryCalc.logicalDayOfMinutes(
           entry.dateTime,
           dayStartOffsetMinutes,
         ),
         payloadDigest: _waterPayloadDigest(entry),
       );

  final WaterIntakeEntity entry;

  @override
  bool matchesTargetEntity(Object entity) =>
      entity is WaterIntakeEntity &&
      entity.id == entry.id &&
      _waterPayloadDigest(entity) == payloadDigest;
}

/// Confirmation choices used to freeze a preview into a manifest.
class LifesumImportSelection {
  const LifesumImportSelection({
    this.includeFood = true,
    this.includeActivity = true,
    this.includeWeights = true,
    this.includeBodyMeasurements = true,
    this.includeEstimatedWater = false,
  });

  final bool includeFood;
  final bool includeActivity;
  final bool includeWeights;
  final bool includeBodyMeasurements;

  /// Estimated water is user-provided history and therefore default-off.
  final bool includeEstimatedWater;

  LifesumImportSelection copyWith({
    bool? includeFood,
    bool? includeActivity,
    bool? includeWeights,
    bool? includeBodyMeasurements,
    bool? includeEstimatedWater,
  }) => LifesumImportSelection(
    includeFood: includeFood ?? this.includeFood,
    includeActivity: includeActivity ?? this.includeActivity,
    includeWeights: includeWeights ?? this.includeWeights,
    includeBodyMeasurements:
        includeBodyMeasurements ?? this.includeBodyMeasurements,
    includeEstimatedWater: includeEstimatedWater ?? this.includeEstimatedWater,
  );
}

/// An immutable, deterministic plan produced only from conflict-free preview
/// candidates and explicit confirmation choices.
///
/// Recipes cannot appear here until Stable has a snapshot-capable model. Food
/// and activity operations expose [requiresTrackedDayPolicy] so no executor can
/// mistake this primary-record plan for a complete historical diary mutation.
class LifesumImportManifest {
  LifesumImportManifest._({
    required this.manifestId,
    required this.dayStartOffsetMinutes,
    required this.selection,
    required List<LifesumImportOperation> operations,
    required List<DateTime> affectedTrackedDays,
  }) : operations = List<LifesumImportOperation>.unmodifiable(operations),
       affectedTrackedDays = List<DateTime>.unmodifiable(affectedTrackedDays);

  factory LifesumImportManifest.fromPreview(
    LifesumImportPreview preview, {
    LifesumImportSelection selection = const LifesumImportSelection(),
  }) {
    final operations = <LifesumImportOperation>[];
    final measurements = preview.measurements;

    if (selection.includeWeights && measurements != null) {
      final entries = measurements.weightsToAdd.toList()
        ..sort((left, right) => left.date.compareTo(right.date));
      operations.addAll(entries.map(LifesumWeightImportOperation.new));
    }
    if (selection.includeBodyMeasurements && measurements != null) {
      final entries = measurements.bodyMeasurementsToAdd.toList()
        ..sort((left, right) => left.date.compareTo(right.date));
      operations.addAll(entries.map(LifesumBodyMeasurementImportOperation.new));
    }
    if (selection.includeFood && preview.food != null) {
      final entries =
          preview.food!.candidatesToAdd
              .map((candidate) => candidate.intake)
              .toList()
            ..sort(_compareIntakes);
      operations.addAll(
        entries.map(
          (entry) => LifesumIntakeImportOperation(
            entry,
            dayStartOffsetMinutes: preview.dayStartOffsetMinutes,
          ),
        ),
      );
    }
    if (selection.includeActivity && preview.activity != null) {
      final entries =
          preview.activity!.candidatesToAdd
              .map((candidate) => candidate.activity)
              .toList()
            ..sort(_compareActivities);
      operations.addAll(
        entries.map(
          (entry) => LifesumActivityImportOperation(
            entry,
            dayStartOffsetMinutes: preview.dayStartOffsetMinutes,
          ),
        ),
      );
    }
    if (selection.includeEstimatedWater && preview.estimatedWater != null) {
      final entries = preview.estimatedWater!.candidates.toList()
        ..sort(_compareWater);
      operations.addAll(
        entries.map(
          (entry) => LifesumEstimatedWaterImportOperation(
            entry,
            dayStartOffsetMinutes: preview.dayStartOffsetMinutes,
          ),
        ),
      );
    }

    final operationIds = operations
        .map((operation) => operation.operationId)
        .toList(growable: false);
    if (operationIds.toSet().length != operationIds.length) {
      throw StateError('Lifesum manifest contains duplicate operation IDs');
    }

    final affectedDayKeys = <int, DateTime>{};
    for (final operation in operations) {
      if (operation.kind != LifesumImportOperationKind.intake &&
          operation.kind != LifesumImportOperationKind.activity) {
        continue;
      }
      final day = operation.logicalDay;
      affectedDayKeys[_dayKey(day)] = day;
    }
    final affectedTrackedDays = affectedDayKeys.values.toList()..sort();
    return _fromOperations(
      dayStartOffsetMinutes: preview.dayStartOffsetMinutes,
      selection: selection,
      operations: operations,
      affectedTrackedDays: affectedTrackedDays,
    );
  }

  final String manifestId;
  final int dayStartOffsetMinutes;
  final LifesumImportSelection selection;
  final List<LifesumImportOperation> operations;
  final List<DateTime> affectedTrackedDays;

  int get operationCount => operations.length;
  bool get isEmpty => operations.isEmpty;
  bool get includesEstimatedData => operations.any(
    (operation) => operation.kind == LifesumImportOperationKind.estimatedWater,
  );

  /// Historical tracked-day goals still need an explicit user-facing policy
  /// before food or activity manifests can be executed.
  bool get requiresTrackedDayPolicy {
    final requiredDays = affectedTrackedDays.map(_dayKey).toSet();
    if (requiredDays.isEmpty) return false;
    final plannedDays = operations
        .where(
          (operation) =>
              operation.kind == LifesumImportOperationKind.trackedDay,
        )
        .map((operation) => _dayKey(operation.logicalDay))
        .toSet();
    return !plannedDays.containsAll(requiredDays);
  }

  bool get isExecutable => !requiresTrackedDayPolicy;

  int operationCountFor(LifesumImportOperationKind kind) =>
      operations.where((operation) => operation.kind == kind).length;

  /// Adds the explicit historical tracked-day result and produces the final
  /// manifest identity that a journal may execute.
  LifesumImportManifest withTrackedDays(
    Iterable<TrackedDayEntity> trackedDays,
  ) {
    if (operations.any(
      (operation) => operation.kind == LifesumImportOperationKind.trackedDay,
    )) {
      throw StateError('Lifesum manifest already contains tracked days');
    }
    final entries = trackedDays.toList(growable: false)
      ..sort((left, right) => left.day.compareTo(right.day));
    final expectedKeys = affectedTrackedDays.map(_dayKey).toSet();
    final actualKeys = entries.map((entry) => _dayKey(entry.day)).toList();
    if (actualKeys.toSet().length != actualKeys.length ||
        actualKeys.toSet().length != expectedKeys.length ||
        !actualKeys.toSet().containsAll(expectedKeys)) {
      throw StateError(
        'Tracked-day plan does not cover the Lifesum manifest exactly',
      );
    }

    final firstPrimaryIndex = operations.indexWhere(
      (operation) =>
          operation.kind == LifesumImportOperationKind.intake ||
          operation.kind == LifesumImportOperationKind.activity ||
          operation.kind == LifesumImportOperationKind.estimatedWater,
    );
    final insertionIndex = firstPrimaryIndex == -1
        ? operations.length
        : firstPrimaryIndex;
    final completedOperations = <LifesumImportOperation>[
      ...operations.take(insertionIndex),
      ...entries.map(LifesumTrackedDayImportOperation.new),
      ...operations.skip(insertionIndex),
    ];
    return _fromOperations(
      dayStartOffsetMinutes: dayStartOffsetMinutes,
      selection: selection,
      operations: completedOperations,
      affectedTrackedDays: affectedTrackedDays,
    );
  }

  static LifesumImportManifest _fromOperations({
    required int dayStartOffsetMinutes,
    required LifesumImportSelection selection,
    required List<LifesumImportOperation> operations,
    required List<DateTime> affectedTrackedDays,
  }) {
    final operationIds = operations
        .map((operation) => operation.operationId)
        .toList(growable: false);
    if (operationIds.toSet().length != operationIds.length) {
      throw StateError('Lifesum manifest contains duplicate operation IDs');
    }
    final signature = <String>[
      'lifesum-import-manifest-v2',
      'offset:$dayStartOffsetMinutes',
      ...operationIds,
    ].join('\u001f');
    return LifesumImportManifest._(
      manifestId: 'lifesum-manifest-${_stableDigest(signature)}',
      dayStartOffsetMinutes: dayStartOffsetMinutes,
      selection: selection,
      operations: operations,
      affectedTrackedDays: affectedTrackedDays,
    );
  }
}

int _compareIntakes(IntakeEntity left, IntakeEntity right) {
  final dateComparison = left.dateTime.compareTo(right.dateTime);
  return dateComparison != 0 ? dateComparison : left.id.compareTo(right.id);
}

int _compareActivities(UserActivityEntity left, UserActivityEntity right) {
  final dateComparison = left.date.compareTo(right.date);
  return dateComparison != 0 ? dateComparison : left.id.compareTo(right.id);
}

int _compareWater(WaterIntakeEntity left, WaterIntakeEntity right) {
  final dateComparison = left.dateTime.compareTo(right.dateTime);
  return dateComparison != 0 ? dateComparison : left.id.compareTo(right.id);
}

DateTime _calendarDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);

int _dayKey(DateTime date) => date.year * 10000 + date.month * 100 + date.day;

String _dateSlug(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}'
    '${date.month.toString().padLeft(2, '0')}'
    '${date.day.toString().padLeft(2, '0')}';

String _weightPayloadDigest(WeightLogEntity entry) =>
    _stableDigest(_canonical(<Object?>[entry.weightKg, entry.note]));

String _bodyMeasurementPayloadDigest(BodyMeasurementLogEntity entry) =>
    _stableDigest(
      _canonical(<Object?>[
        entry.waistCm,
        entry.hipsCm,
        entry.chestCm,
        entry.armCm,
        entry.thighCm,
        entry.bodyFatPercent,
        entry.note,
      ]),
    );

String _trackedDayPayloadDigest(TrackedDayEntity entry) => _stableDigest(
  _canonical(<Object?>[
    entry.calorieGoal,
    entry.caloriesTracked,
    entry.carbsGoal,
    entry.carbsTracked,
    entry.fatGoal,
    entry.fatTracked,
    entry.proteinGoal,
    entry.proteinTracked,
    entry.fibreGoal,
    entry.satFatGoal,
    entry.sugarsGoal,
    entry.sodiumGoal,
    entry.calciumGoal,
    entry.ironGoal,
    entry.potassiumGoal,
    entry.vitaminDGoal,
    entry.vitaminB12Goal,
    entry.magnesiumGoal,
  ]),
);

String _intakePayloadDigest(IntakeEntity entry) => _stableDigest(
  _canonical(<Object?>[
    entry.unit,
    entry.amount,
    entry.type.name,
    entry.dateTime.microsecondsSinceEpoch,
    _mealPayload(entry.meal),
  ]),
);

List<Object?> _mealPayload(MealEntity meal) => <Object?>[
  meal.code,
  meal.name,
  meal.brands,
  meal.thumbnailImageUrl,
  meal.mainImageUrl,
  meal.url,
  meal.mealQuantity,
  meal.mealUnit,
  meal.servingQuantity,
  meal.servingUnit,
  meal.servingSize,
  meal.source.name,
  meal.backendSource,
  meal.machineTranslatedName,
  meal.isFavorite,
  meal.isRescue,
  meal.localImagePath,
  meal.detailed,
  <Object?>[
    meal.nutriments.energyKcal100,
    meal.nutriments.carbohydrates100,
    meal.nutriments.fat100,
    meal.nutriments.proteins100,
    meal.nutriments.sugars100,
    meal.nutriments.saturatedFat100,
    meal.nutriments.fiber100,
    meal.nutriments.monounsaturatedFat100,
    meal.nutriments.polyunsaturatedFat100,
    meal.nutriments.transFat100,
    meal.nutriments.cholesterol100,
    meal.nutriments.sodium100,
    meal.nutriments.potassium100,
    meal.nutriments.magnesium100,
    meal.nutriments.calcium100,
    meal.nutriments.iron100,
    meal.nutriments.zinc100,
    meal.nutriments.phosphorus100,
    meal.nutriments.vitaminA100,
    meal.nutriments.vitaminC100,
    meal.nutriments.vitaminD100,
    meal.nutriments.vitaminB6100,
    meal.nutriments.vitaminB12100,
    meal.nutriments.niacin100,
  ],
];

String _activityPayloadDigest(UserActivityEntity entry) => _stableDigest(
  _canonical(<Object?>[
    entry.duration,
    entry.burnedKcal,
    entry.date.microsecondsSinceEpoch,
    entry.userKcal,
    entry.physicalActivityEntity.code,
    entry.physicalActivityEntity.specificActivity,
    entry.physicalActivityEntity.description,
    entry.physicalActivityEntity.mets,
    entry.physicalActivityEntity.tags,
    entry.physicalActivityEntity.type.name,
  ]),
);

String _waterPayloadDigest(WaterIntakeEntity entry) => _stableDigest(
  _canonical(<Object?>[entry.dateTime.microsecondsSinceEpoch, entry.amountMl]),
);

String _canonical(List<Object?> values) => values.map(_canonicalValue).join();

String _canonicalValue(Object? value) {
  if (value == null) return 'n;';
  if (value is bool) return value ? 'b:1;' : 'b:0;';
  if (value is num) return 'd:${value.toString().length}:${value.toString()};';
  if (value is String) return 's:${value.length}:$value;';
  if (value is List<Object?>) {
    final encoded = value.map(_canonicalValue).join();
    return 'l:${value.length}:${encoded.length}:$encoded;';
  }
  throw ArgumentError.value(value, 'value', 'Unsupported canonical value');
}

String _stableDigest(String input) {
  var fnv = 0x811c9dc5;
  var djb = 5381;
  for (final unit in input.codeUnits) {
    fnv ^= unit;
    fnv = (fnv * 0x01000193) & 0xffffffff;
    djb = (((djb << 5) + djb) ^ unit) & 0xffffffff;
  }
  return '${fnv.toRadixString(16).padLeft(8, '0')}'
      '${djb.toRadixString(16).padLeft(8, '0')}';
}
