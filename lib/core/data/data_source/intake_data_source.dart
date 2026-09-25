import 'package:collection/collection.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_type_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';

class IntakeDataSource {
  final log = Logger('IntakeDataSource');
  final HiveDBProvider _db;

  IntakeDataSource(this._db);

  Box<IntakeDBO> get _intakeBox => _db.intakeBox;

  Future<void> addIntake(IntakeDBO intakeDBO) async {
    log.fine('Adding new intake item to db');
    await _intakeBox.add(intakeDBO);
  }

  Future<void> addAllIntakes(List<IntakeDBO> intakeDBOList) async {
    log.fine('Adding new intake items to db');
    await _intakeBox.addAll(intakeDBOList);
  }

  Future<void> deleteIntakeFromId(String intakeId) async {
    log.fine('Deleting intake item from db');
    final toDelete = _intakeBox.values
        .where((dbo) => dbo.id == intakeId)
        .toList();
    for (final element in toDelete) {
      await element.delete();
    }
  }

  Future<IntakeDBO?> updateIntake(
    String intakeId,
    Map<String, dynamic> fields,
  ) async {
    log.fine(
      'Updating intake $intakeId with fields ${fields.toString()} in db',
    );
    var intakeObject = _intakeBox.values.indexed
        .where((indexedDbo) => indexedDbo.$2.id == intakeId)
        .firstOrNull;
    if (intakeObject == null) {
      log.fine('Cannot update intake $intakeId as it is non existent');
      return null;
    }
    intakeObject.$2.amount = fields['amount'] ?? intakeObject.$2.amount;
    await _intakeBox.putAt(intakeObject.$1, intakeObject.$2);
    return _intakeBox.getAt(intakeObject.$1);
  }

  /// Writes [intakeDBO] over the entry with its id, in the same place, or
  /// adds it when there is none (a removal being undone).
  Future<void> putIntake(IntakeDBO intakeDBO) async {
    final index = _intakeBox.values.toList().indexWhere(
      (dbo) => dbo.id == intakeDBO.id,
    );
    if (index < 0) {
      await _intakeBox.add(intakeDBO);
    } else {
      await _intakeBox.putAt(index, intakeDBO);
    }
  }

  Future<IntakeDBO?> getIntakeById(String intakeId) async {
    return _intakeBox.values.firstWhereOrNull(
      (intake) => intake.id == intakeId,
    );
  }

  Future<List<IntakeDBO>> getAllIntakes() async {
    return _intakeBox.values.toList();
  }

  Future<List<IntakeDBO>> getAllIntakesByDate(
    IntakeTypeDBO intakeType,
    DateTime dateTime, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async {
    // #139: when a non-zero day-start offset is configured, an entry
    // logged before that hour rolls into the previous wall-clock day.
    // A zero total offset preserves the original wall-clock behaviour.
    // The follow-up to #139 adds a minutes companion; both compose
    // additively into a single total-minutes value here.
    //
    // [dateTime] is a day *label* — the calendar date the caller is asking
    // about — so only the stored timestamp is resolved through the boundary.
    // Resolving both is what made a configured boundary shift the whole
    // selection: subtracting the offset from a midnight label lands in the
    // previous day, so tapping the 20th listed the 19th's entries.
    //
    // No zero-offset fast path is needed: the predicate reduces to plain
    // calendar-day equality when no offset is set.
    final inDay = DayBoundaryCalc.logicalDayMatcher(
      dateTime,
      DayBoundaryCalc.totalMinutesOf(
        dayStartOffsetHours,
        dayStartOffsetMinutes,
      ),
    );
    return _intakeBox.values
        .where((intake) => intake.type == intakeType && inDay(intake.dateTime))
        .toList();
  }

  /// The foods eaten most recently, newest first, one row per food.
  ///
  /// Ordered purely by when the food was eaten, so today's soup is on top
  /// tomorrow and last week's pie is a short scroll further down. Custom foods
  /// used to be listed ahead of everything else, which buried every searched
  /// or scanned food under hundreds of imported Lifesum snapshots.
  ///
  /// A food counts once by its code (or name), and once by what it is: the
  /// Lifesum import gives every logged copy of the same food its own code.
  Future<List<IntakeDBO>> getRecentlyAddedIntake({int number = 100000}) async {
    // Newest first; entries on the same moment (day labels) keep the order
    // they were logged in, latest first.
    final intakeList = _intakeBox.values.toList().indexed.toList()
      ..sort((a, b) {
        final byTime = b.$2.dateTime.compareTo(a.$2.dateTime);
        return byTime != 0 ? byTime : b.$1.compareTo(a.$1);
      });

    final seen = <String>{};
    final uniqueIntake = <IntakeDBO>[];
    for (final (_, intake) in intakeList) {
      final codeKey = 'code:${intake.meal.code ?? intake.meal.name ?? ''}';
      final sameFoodKey = _sameFoodKey(intake.meal);
      final isNew =
          !seen.contains(codeKey) &&
          (sameFoodKey == null || !seen.contains(sameFoodKey));
      seen.add(codeKey);
      if (sameFoodKey != null) seen.add(sameFoodKey);
      if (isNew) uniqueIntake.add(intake);
      if (uniqueIntake.length >= number) break;
    }
    return uniqueIntake;
  }

  /// Equal for copies of one food: same source, name, brand, serving and
  /// nutrition. Different products never share it, even with the same name.
  /// Null for a nameless food, which cannot be told apart from another.
  static String? _sameFoodKey(MealDBO meal) {
    String text(String? value) =>
        (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    String number(double? value) => value?.toStringAsFixed(1) ?? '-';
    if (text(meal.name).isEmpty) return null;
    final n = meal.nutriments;
    return [
      'food',
      meal.source.name,
      text(meal.name),
      text(meal.brands),
      text(meal.mealUnit),
      number(meal.servingQuantity),
      text(meal.servingUnit),
      number(n.energyKcal100),
      number(n.carbohydrates100),
      number(n.fat100),
      number(n.proteins100),
    ].join('\u001f');
  }

  Future<List<IntakeDBO>> getCustomMealIntakes() async {
    return _intakeBox.values
        .where((dbo) => dbo.meal.source == MealSourceDBO.custom)
        .toList();
  }

  /// Replace the denormalised [MealDBO] snapshot on every intake whose
  /// `(meal.code ?? meal.name)` matches [fromMealKey] *and* whose meal source
  /// is custom. Used by the custom-meal merge flow: callers compute the
  /// kcal/macro deltas before invoking this and apply them to TrackedDay
  /// totals separately.
  ///
  /// Returns the list of `(oldIntake, newIntake)` pairs that were rewritten,
  /// so the caller can recompute totals from the diff.
  Future<List<(IntakeDBO, IntakeDBO)>> remapCustomMealOnIntakes({
    required String fromMealKey,
    required MealDBO toMeal,
  }) async {
    final rewrites = <(IntakeDBO, IntakeDBO)>[];
    final entries = _intakeBox.toMap().entries.toList();
    for (final entry in entries) {
      final dbo = entry.value;
      if (dbo.meal.source != MealSourceDBO.custom) continue;
      final key = dbo.meal.code ?? dbo.meal.name;
      if (key != fromMealKey) continue;
      final updated = IntakeDBO(
        id: dbo.id,
        unit: dbo.unit,
        amount: dbo.amount,
        type: dbo.type,
        meal: toMeal,
        dateTime: dbo.dateTime,
      );
      await _intakeBox.put(entry.key, updated);
      rewrites.add((dbo, updated));
    }
    return rewrites;
  }
}
