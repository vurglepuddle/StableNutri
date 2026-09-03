import 'package:opennutritracker/core/data/repository/body_measurement_log_repository.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/data/repository/water_intake_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_preview.dart';

enum LifesumExistingHistoryFailure { activeProfileChanged }

class LifesumExistingHistoryException implements Exception {
  const LifesumExistingHistoryException(this.failure);

  final LifesumExistingHistoryFailure failure;

  @override
  String toString() => 'Lifesum history snapshot failed: $failure';
}

/// One immutable read of every collection used by conflict classification.
class LifesumExistingHistory {
  LifesumExistingHistory({
    required this.profileId,
    required List<IntakeEntity> intakes,
    required List<UserActivityEntity> activities,
    required List<WeightLogEntity> weights,
    required List<BodyMeasurementLogEntity> bodyMeasurements,
    required List<TrackedDayEntity> trackedDays,
    required List<WaterIntakeEntity> waterEntries,
    required List<RecipeEntity> recipes,
  }) : intakes = List<IntakeEntity>.unmodifiable(intakes),
       activities = List<UserActivityEntity>.unmodifiable(activities),
       weights = List<WeightLogEntity>.unmodifiable(weights),
       bodyMeasurements = List<BodyMeasurementLogEntity>.unmodifiable(
         bodyMeasurements,
       ),
       trackedDays = List<TrackedDayEntity>.unmodifiable(trackedDays),
       waterEntries = List<WaterIntakeEntity>.unmodifiable(waterEntries),
       recipes = List<RecipeEntity>.unmodifiable(recipes);

  final String profileId;
  final List<IntakeEntity> intakes;
  final List<UserActivityEntity> activities;
  final List<WeightLogEntity> weights;
  final List<BodyMeasurementLogEntity> bodyMeasurements;
  final List<TrackedDayEntity> trackedDays;
  final List<WaterIntakeEntity> waterEntries;
  final List<RecipeEntity> recipes;

  LifesumImportPreview buildPreview(
    LifesumArchiveCsvSelection selection, {
    int dayStartOffsetMinutes = 0,
    int estimatedWaterAmountPerDayMl = 2000,
  }) => LifesumImportPreview.fromSelection(
    selection,
    existingIntakes: intakes,
    existingActivities: activities,
    existingWeights: weights,
    existingBodyMeasurements: bodyMeasurements,
    existingRecipes: recipes,
    existingTrackedDays: trackedDays,
    existingWaterEntries: waterEntries,
    dayStartOffsetMinutes: dayStartOffsetMinutes,
    estimatedWaterAmountPerDayMl: estimatedWaterAmountPerDayMl,
  );
}

/// Loads conflict inputs concurrently and rejects a mixed-profile snapshot.
///
/// The callback constructor keeps this boundary independently testable. The
/// repository factory is the production wiring and performs reads only.
class LifesumExistingHistoryLoader {
  LifesumExistingHistoryLoader({
    required String Function() activeProfileId,
    required int Function() activeProfileGeneration,
    required Future<List<IntakeEntity>> Function() loadIntakes,
    required Future<List<UserActivityEntity>> Function() loadActivities,
    required Future<List<WeightLogEntity>> Function() loadWeights,
    required Future<List<BodyMeasurementLogEntity>> Function()
    loadBodyMeasurements,
    required Future<List<TrackedDayEntity>> Function() loadTrackedDays,
    required Future<List<WaterIntakeEntity>> Function() loadWaterEntries,
    required Future<List<RecipeEntity>> Function() loadRecipes,
  }) : _activeProfileId = activeProfileId,
       _activeProfileGeneration = activeProfileGeneration,
       _loadIntakes = loadIntakes,
       _loadActivities = loadActivities,
       _loadWeights = loadWeights,
       _loadBodyMeasurements = loadBodyMeasurements,
       _loadTrackedDays = loadTrackedDays,
       _loadWaterEntries = loadWaterEntries,
       _loadRecipes = loadRecipes;

  factory LifesumExistingHistoryLoader.fromRepositories({
    required HiveDBProvider database,
    required IntakeRepository intakeRepository,
    required UserActivityRepository activityRepository,
    required WeightLogRepository weightRepository,
    required BodyMeasurementLogRepository bodyMeasurementRepository,
    required TrackedDayRepository trackedDayRepository,
    required WaterIntakeRepository waterRepository,
    required RecipeRepository recipeRepository,
  }) => LifesumExistingHistoryLoader(
    activeProfileId: () => database.activeProfileId,
    activeProfileGeneration: () => database.activeProfileGeneration,
    loadIntakes: () async => (await intakeRepository.getAllIntakesDBO())
        .map(IntakeEntity.fromIntakeDBO)
        .toList(),
    loadActivities: () async =>
        (await activityRepository.getAllUserActivityDBO())
            .map(UserActivityEntity.fromUserActivityDBO)
            .toList(),
    loadWeights: weightRepository.getAllEntries,
    loadBodyMeasurements: bodyMeasurementRepository.getAllEntries,
    loadTrackedDays: () async =>
        (await trackedDayRepository.getAllTrackedDaysDBO())
            .map(TrackedDayEntity.fromTrackedDayDBO)
            .toList(),
    loadWaterEntries: waterRepository.getAllEntries,
    loadRecipes: () async => recipeRepository.getAllRecipes(),
  );

  final String Function() _activeProfileId;
  final int Function() _activeProfileGeneration;
  final Future<List<IntakeEntity>> Function() _loadIntakes;
  final Future<List<UserActivityEntity>> Function() _loadActivities;
  final Future<List<WeightLogEntity>> Function() _loadWeights;
  final Future<List<BodyMeasurementLogEntity>> Function() _loadBodyMeasurements;
  final Future<List<TrackedDayEntity>> Function() _loadTrackedDays;
  final Future<List<WaterIntakeEntity>> Function() _loadWaterEntries;
  final Future<List<RecipeEntity>> Function() _loadRecipes;

  Future<LifesumExistingHistory> load() async {
    final profileId = _activeProfileId();
    final profileGeneration = _activeProfileGeneration();
    final results = await Future.wait<Object>(<Future<Object>>[
      _loadIntakes(),
      _loadActivities(),
      _loadWeights(),
      _loadBodyMeasurements(),
      _loadTrackedDays(),
      _loadWaterEntries(),
      _loadRecipes(),
    ]);
    if (_activeProfileId() != profileId ||
        _activeProfileGeneration() != profileGeneration) {
      throw const LifesumExistingHistoryException(
        LifesumExistingHistoryFailure.activeProfileChanged,
      );
    }
    return LifesumExistingHistory(
      profileId: profileId,
      intakes: results[0] as List<IntakeEntity>,
      activities: results[1] as List<UserActivityEntity>,
      weights: results[2] as List<WeightLogEntity>,
      bodyMeasurements: results[3] as List<BodyMeasurementLogEntity>,
      trackedDays: results[4] as List<TrackedDayEntity>,
      waterEntries: results[5] as List<WaterIntakeEntity>,
      recipes: results[6] as List<RecipeEntity>,
    );
  }
}
