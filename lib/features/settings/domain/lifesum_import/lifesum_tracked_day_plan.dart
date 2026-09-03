import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/utils/calc/macro_calc.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_manifest.dart';

/// The export contains no historical calorie or macro goals. This policy is
/// therefore explicit confirmation data, not a claim about Lifesum history.
enum LifesumHistoricalGoalPolicy { copyCurrentProfileTargets }

class LifesumHistoricalGoalSnapshot {
  LifesumHistoricalGoalSnapshot({
    required this.calorieGoal,
    required this.carbsGoal,
    required this.fatGoal,
    required this.proteinGoal,
  }) {
    final values = <double>[calorieGoal, carbsGoal, fatGoal, proteinGoal];
    if (values.any((value) => !value.isFinite || value < 0) ||
        calorieGoal == 0) {
      throw ArgumentError('Historical goal snapshot must be finite and valid');
    }
  }

  final double calorieGoal;
  final double carbsGoal;
  final double fatGoal;
  final double proteinGoal;
}

class LifesumTrackedDayPlanEntry {
  const LifesumTrackedDayPlanEntry({
    required this.trackedDay,
    required this.intakeCount,
    required this.activityCount,
    required this.activityCaloriesBurned,
  });

  final TrackedDayEntity trackedDay;
  final int intakeCount;
  final int activityCount;
  final double activityCaloriesBurned;
}

/// Completes the historical diary portion of a primary import manifest.
///
/// Activity energy raises calorie and macro goals exactly as Stable's normal
/// activity-add flow does. Intake totals populate tracked consumption. A day
/// already present in Stable is never replaced; callers must rebuild the
/// preview with those tracked days so its primary operations are excluded too.
class LifesumTrackedDayPlan {
  LifesumTrackedDayPlan._({
    required this.sourceManifestId,
    required this.policy,
    required this.goals,
    required this.sourceAffectedDayCount,
    required this.existingDayCount,
    required List<LifesumTrackedDayPlanEntry> entries,
  }) : entries = List<LifesumTrackedDayPlanEntry>.unmodifiable(entries);

  factory LifesumTrackedDayPlan.fromManifest(
    LifesumImportManifest manifest, {
    required LifesumHistoricalGoalSnapshot goals,
    LifesumHistoricalGoalPolicy policy =
        LifesumHistoricalGoalPolicy.copyCurrentProfileTargets,
    Iterable<TrackedDayEntity> existingTrackedDays = const <TrackedDayEntity>[],
  }) {
    if (manifest.operationCountFor(LifesumImportOperationKind.trackedDay) > 0) {
      throw StateError('Lifesum manifest already has a tracked-day plan');
    }
    final builders = <int, _TrackedDayBuilder>{};
    for (final operation in manifest.operations) {
      switch (operation) {
        case LifesumIntakeImportOperation():
          builders
              .putIfAbsent(
                _dayKey(operation.logicalDay),
                () => _TrackedDayBuilder(operation.logicalDay),
              )
              .addIntake(operation.entry);
        case LifesumActivityImportOperation():
          builders
              .putIfAbsent(
                _dayKey(operation.logicalDay),
                () => _TrackedDayBuilder(operation.logicalDay),
              )
              .addActivity(operation.entry.effectiveBurnedKcal);
        default:
          break;
      }
    }

    final existingKeys = existingTrackedDays
        .map((entry) => _dayKey(entry.day))
        .toSet();
    var existingDayCount = 0;
    final entries = <LifesumTrackedDayPlanEntry>[];
    final sortedBuilders = builders.values.toList()
      ..sort((left, right) => left.day.compareTo(right.day));
    for (final builder in sortedBuilders) {
      if (existingKeys.contains(_dayKey(builder.day))) {
        existingDayCount++;
        continue;
      }
      entries.add(builder.build(goals));
    }
    return LifesumTrackedDayPlan._(
      sourceManifestId: manifest.manifestId,
      policy: policy,
      goals: goals,
      sourceAffectedDayCount: builders.length,
      existingDayCount: existingDayCount,
      entries: entries,
    );
  }

  final String sourceManifestId;
  final LifesumHistoricalGoalPolicy policy;
  final LifesumHistoricalGoalSnapshot goals;
  final int sourceAffectedDayCount;
  final int existingDayCount;
  final List<LifesumTrackedDayPlanEntry> entries;

  int get candidateDayCount => entries.length;
  bool get hasExistingDayConflicts => existingDayCount > 0;
  bool get canCompleteManifest =>
      !hasExistingDayConflicts && candidateDayCount == sourceAffectedDayCount;

  LifesumImportManifest completeManifest(LifesumImportManifest manifest) {
    if (manifest.manifestId != sourceManifestId || !canCompleteManifest) {
      throw StateError('Tracked-day plan cannot complete this manifest');
    }
    return manifest.withTrackedDays(entries.map((entry) => entry.trackedDay));
  }
}

class _TrackedDayBuilder {
  _TrackedDayBuilder(this.day);

  final DateTime day;
  var intakeCount = 0;
  var activityCount = 0;
  var caloriesTracked = 0.0;
  var carbsTracked = 0.0;
  var fatTracked = 0.0;
  var proteinTracked = 0.0;
  var activityCaloriesBurned = 0.0;

  void addIntake(IntakeEntity entry) {
    intakeCount++;
    caloriesTracked += entry.totalKcal;
    carbsTracked += entry.totalCarbsGram;
    fatTracked += entry.totalFatsGram;
    proteinTracked += entry.totalProteinsGram;
  }

  void addActivity(double caloriesBurned) {
    activityCount++;
    activityCaloriesBurned += caloriesBurned;
  }

  LifesumTrackedDayPlanEntry build(LifesumHistoricalGoalSnapshot goals) {
    return LifesumTrackedDayPlanEntry(
      trackedDay: TrackedDayEntity(
        day: day,
        calorieGoal: goals.calorieGoal + activityCaloriesBurned,
        caloriesTracked: caloriesTracked,
        carbsGoal:
            goals.carbsGoal +
            MacroCalc.getTotalCarbsGoal(activityCaloriesBurned),
        carbsTracked: carbsTracked,
        fatGoal:
            goals.fatGoal + MacroCalc.getTotalFatsGoal(activityCaloriesBurned),
        fatTracked: fatTracked,
        proteinGoal:
            goals.proteinGoal +
            MacroCalc.getTotalProteinsGoal(activityCaloriesBurned),
        proteinTracked: proteinTracked,
      ),
      intakeCount: intakeCount,
      activityCount: activityCount,
      activityCaloriesBurned: activityCaloriesBurned,
    );
  }
}

int _dayKey(DateTime date) => date.year * 10000 + date.month * 100 + date.day;
