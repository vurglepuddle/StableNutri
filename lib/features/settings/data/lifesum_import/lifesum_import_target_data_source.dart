import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_dbo.dart';
import 'package:opennutritracker/core/data/dbo/body_measurement_log_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/dbo/water_intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/weight_log_dbo.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/extensions.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_executor.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_journal.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_manifest.dart';

enum LifesumImportTargetStoreFailure {
  targetNotAbsent,
  targetChanged,
  profileChanged,
}

class LifesumImportTargetStoreException implements Exception {
  const LifesumImportTargetStoreException(this.failure);

  final LifesumImportTargetStoreFailure failure;

  @override
  String toString() => 'Lifesum target store error: $failure';
}

/// Conditional Hive writes for one captured active-profile session.
///
/// Every operation is checked immediately before mutation. The data source
/// keeps the exact box instances and profile generation it was created with,
/// so a profile switch closes this session instead of redirecting later
/// operations into another profile.
class LifesumImportTargetDataSource implements LifesumImportTargetStore {
  LifesumImportTargetDataSource(HiveDBProvider database)
    : _database = database,
      _profileId = database.activeProfileId,
      _profileGeneration = database.activeProfileGeneration,
      _intakeBox = database.intakeBox,
      _activityBox = database.userActivityBox,
      _trackedDayBox = database.trackedDayBox,
      _weightBox = database.weightLogBox,
      _bodyMeasurementBox = database.bodyMeasurementLogBox,
      _waterBox = database.waterIntakeBox;

  final HiveDBProvider _database;
  final String _profileId;
  final int _profileGeneration;
  final Box<IntakeDBO> _intakeBox;
  final Box<UserActivityDBO> _activityBox;
  final Box<TrackedDayDBO> _trackedDayBox;
  final Box<WeightLogDBO> _weightBox;
  final Box<BodyMeasurementLogDBO> _bodyMeasurementBox;
  final Box<WaterIntakeDBO> _waterBox;

  @override
  Future<LifesumImportTargetProbe> probe(
    LifesumImportOperation operation,
  ) async {
    _requireProfile();
    return _locate(operation).probe;
  }

  @override
  Future<void> apply(LifesumImportOperation operation) async {
    _requireProfile();
    if (_locate(operation).probe != LifesumImportTargetProbe.absent) {
      throw const LifesumImportTargetStoreException(
        LifesumImportTargetStoreFailure.targetNotAbsent,
      );
    }

    switch (operation) {
      case LifesumWeightImportOperation():
        await _weightBox.put(
          operation.entry.date.toParsedDay(),
          WeightLogDBO.fromWeightLogEntity(operation.entry),
        );
      case LifesumBodyMeasurementImportOperation():
        await _bodyMeasurementBox.put(
          operation.entry.date.toParsedDay(),
          BodyMeasurementLogDBO.fromEntity(operation.entry),
        );
      case LifesumTrackedDayImportOperation():
        await _trackedDayBox.put(
          operation.entry.day.toParsedDay(),
          TrackedDayDBO.fromTrackedDayEntity(operation.entry),
        );
      case LifesumIntakeImportOperation():
        await _intakeBox.put(
          operation.entry.id,
          IntakeDBO.fromIntakeEntity(operation.entry),
        );
      case LifesumActivityImportOperation():
        await _activityBox.put(
          operation.entry.id,
          UserActivityDBO.fromUserActivityEntity(operation.entry),
        );
      case LifesumEstimatedWaterImportOperation():
        await _waterBox.put(
          operation.entry.id,
          WaterIntakeDBO.fromWaterIntakeEntity(operation.entry),
        );
    }
    _requireProfile();
  }

  @override
  Future<void> rollback(LifesumImportOperation operation) async {
    _requireProfile();
    final located = _locate(operation);
    switch (located.probe) {
      case LifesumImportTargetProbe.absent:
        return;
      case LifesumImportTargetProbe.conflicting:
        throw const LifesumImportTargetStoreException(
          LifesumImportTargetStoreFailure.targetChanged,
        );
      case LifesumImportTargetProbe.matching:
        break;
    }

    final storageKey = located.storageKey;
    if (storageKey == null) {
      throw const LifesumImportTargetStoreException(
        LifesumImportTargetStoreFailure.targetChanged,
      );
    }
    switch (operation) {
      case LifesumWeightImportOperation():
        await _weightBox.delete(storageKey);
      case LifesumBodyMeasurementImportOperation():
        await _bodyMeasurementBox.delete(storageKey);
      case LifesumTrackedDayImportOperation():
        await _trackedDayBox.delete(storageKey);
      case LifesumIntakeImportOperation():
        await _intakeBox.delete(storageKey);
      case LifesumActivityImportOperation():
        await _activityBox.delete(storageKey);
      case LifesumEstimatedWaterImportOperation():
        await _waterBox.delete(storageKey);
    }
    _requireProfile();
  }

  _LocatedTarget _locate(LifesumImportOperation operation) =>
      switch (operation) {
        LifesumWeightImportOperation() => _locateAtKey(
          box: _weightBox,
          key: operation.entry.date.toParsedDay(),
          operation: operation,
          toEntity: WeightLogEntity.fromWeightLogDBO,
        ),
        LifesumBodyMeasurementImportOperation() => _locateAtKey(
          box: _bodyMeasurementBox,
          key: operation.entry.date.toParsedDay(),
          operation: operation,
          toEntity: BodyMeasurementLogEntity.fromDBO,
        ),
        LifesumTrackedDayImportOperation() => _locateAtKey(
          box: _trackedDayBox,
          key: operation.entry.day.toParsedDay(),
          operation: operation,
          toEntity: TrackedDayEntity.fromTrackedDayDBO,
        ),
        LifesumIntakeImportOperation() => _locateById(
          box: _intakeBox,
          id: operation.entry.id,
          operation: operation,
          entityId: (dbo) => dbo.id,
          toEntity: IntakeEntity.fromIntakeDBO,
        ),
        LifesumActivityImportOperation() => _locateById(
          box: _activityBox,
          id: operation.entry.id,
          operation: operation,
          entityId: (dbo) => dbo.id,
          toEntity: UserActivityEntity.fromUserActivityDBO,
        ),
        LifesumEstimatedWaterImportOperation() => _locateById(
          box: _waterBox,
          id: operation.entry.id,
          operation: operation,
          entityId: (dbo) => dbo.id,
          toEntity: WaterIntakeEntity.fromWaterIntakeDBO,
        ),
      };

  _LocatedTarget _locateAtKey<T>({
    required Box<T> box,
    required Object key,
    required LifesumImportOperation operation,
    required Object Function(T dbo) toEntity,
  }) {
    final value = box.get(key);
    if (value == null) return const _LocatedTarget.absent();
    return _LocatedTarget(
      probe: operation.matchesTargetEntity(toEntity(value))
          ? LifesumImportTargetProbe.matching
          : LifesumImportTargetProbe.conflicting,
      storageKey: key,
    );
  }

  _LocatedTarget _locateById<T>({
    required Box<T> box,
    required String id,
    required LifesumImportOperation operation,
    required String Function(T dbo) entityId,
    required Object Function(T dbo) toEntity,
  }) {
    final valueAtFutureKey = box.get(id);
    if (valueAtFutureKey != null && entityId(valueAtFutureKey) != id) {
      return const _LocatedTarget.conflicting();
    }
    final candidates = box
        .toMap()
        .entries
        .where((entry) => entityId(entry.value) == id)
        .toList(growable: false);
    if (candidates.isEmpty) return const _LocatedTarget.absent();
    if (candidates.length != 1) return const _LocatedTarget.conflicting();
    final candidate = candidates.single;
    return _LocatedTarget(
      probe: operation.matchesTargetEntity(toEntity(candidate.value))
          ? LifesumImportTargetProbe.matching
          : LifesumImportTargetProbe.conflicting,
      storageKey: candidate.key,
    );
  }

  void _requireProfile() {
    final boxesOpen =
        _intakeBox.isOpen &&
        _activityBox.isOpen &&
        _trackedDayBox.isOpen &&
        _weightBox.isOpen &&
        _bodyMeasurementBox.isOpen &&
        _waterBox.isOpen;
    if (_database.activeProfileId != _profileId ||
        _database.activeProfileGeneration != _profileGeneration ||
        !boxesOpen) {
      throw const LifesumImportTargetStoreException(
        LifesumImportTargetStoreFailure.profileChanged,
      );
    }
  }
}

class _LocatedTarget {
  const _LocatedTarget({required this.probe, required this.storageKey});

  const _LocatedTarget.absent()
    : probe = LifesumImportTargetProbe.absent,
      storageKey = null;

  const _LocatedTarget.conflicting()
    : probe = LifesumImportTargetProbe.conflicting,
      storageKey = null;

  final LifesumImportTargetProbe probe;
  final Object? storageKey;
}
