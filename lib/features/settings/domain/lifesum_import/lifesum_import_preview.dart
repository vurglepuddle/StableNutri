import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_activity_parser.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_estimated_water_plan.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_food_parser.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_measurement_parser.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_measurement_preview.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_recipe_parser.dart';

/// Why an otherwise valid Lifesum candidate is not part of the default
/// "add missing, keep existing" apply set.
enum LifesumImportConflict { exactId, occupiedLogicalDay, normalizedName }

/// A value-preserving candidate paired with conflict metadata.
class LifesumCandidateReview<T> {
  const LifesumCandidateReview({required this.candidate, this.conflict});

  final T candidate;
  final LifesumImportConflict? conflict;

  bool get hasConflict => conflict != null;
}

class LifesumFoodImportPreview {
  LifesumFoodImportPreview._({
    required this.parseResult,
    required List<LifesumCandidateReview<LifesumFoodCandidate>> reviews,
  }) : reviews =
           List<LifesumCandidateReview<LifesumFoodCandidate>>.unmodifiable(
             reviews,
           );

  factory LifesumFoodImportPreview.fromParseResult(
    LifesumFoodParseResult result, {
    Iterable<IntakeEntity> existingIntakes = const <IntakeEntity>[],
    int dayStartOffsetMinutes = 0,
  }) {
    final existing = existingIntakes.toList(growable: false);
    final existingIds = existing.map((entry) => entry.id).toSet();
    final existingDays = existing
        .map((entry) => _logicalDayKey(entry.dateTime, dayStartOffsetMinutes))
        .toSet();
    return LifesumFoodImportPreview._(
      parseResult: result,
      reviews: result.candidates.map((candidate) {
        final intake = candidate.intake;
        final conflict = existingIds.contains(intake.id)
            ? LifesumImportConflict.exactId
            : existingDays.contains(
                _logicalDayKey(intake.dateTime, dayStartOffsetMinutes),
              )
            ? LifesumImportConflict.occupiedLogicalDay
            : null;
        return LifesumCandidateReview<LifesumFoodCandidate>(
          candidate: candidate,
          conflict: conflict,
        );
      }).toList(),
    );
  }

  final LifesumFoodParseResult parseResult;
  final List<LifesumCandidateReview<LifesumFoodCandidate>> reviews;

  int get candidateCount => reviews.length;
  int get readyToAddCount =>
      reviews.where((review) => !review.hasConflict).length;
  int get exactIdConflictCount => reviews
      .where((review) => review.conflict == LifesumImportConflict.exactId)
      .length;
  int get occupiedDayConflictCount => reviews
      .where(
        (review) => review.conflict == LifesumImportConflict.occupiedLogicalDay,
      )
      .length;
  int get existingConflictCount =>
      exactIdConflictCount + occupiedDayConflictCount;
  int get blockingIssueCount => parseResult.blockingIssueCount;
  int get warningCount => parseResult.warningCount;

  List<LifesumFoodCandidate> get candidatesToAdd =>
      List<LifesumFoodCandidate>.unmodifiable(
        reviews
            .where((review) => !review.hasConflict)
            .map((review) => review.candidate),
      );

  DateTime? get earliestCandidateDay => parseResult.trackedDays.isEmpty
      ? null
      : parseResult.trackedDays.first.day;
  DateTime? get latestCandidateDay =>
      parseResult.trackedDays.isEmpty ? null : parseResult.trackedDays.last.day;
}

class LifesumActivityImportPreview {
  LifesumActivityImportPreview._({
    required this.parseResult,
    required List<LifesumCandidateReview<LifesumActivityCandidate>> reviews,
  }) : reviews =
           List<LifesumCandidateReview<LifesumActivityCandidate>>.unmodifiable(
             reviews,
           );

  factory LifesumActivityImportPreview.fromParseResult(
    LifesumActivityParseResult result, {
    Iterable<UserActivityEntity> existingActivities =
        const <UserActivityEntity>[],
    int dayStartOffsetMinutes = 0,
  }) {
    final existing = existingActivities.toList(growable: false);
    final existingIds = existing.map((entry) => entry.id).toSet();
    final existingDays = existing
        .map((entry) => _logicalDayKey(entry.date, dayStartOffsetMinutes))
        .toSet();
    return LifesumActivityImportPreview._(
      parseResult: result,
      reviews: result.candidates.map((candidate) {
        final activity = candidate.activity;
        final conflict = existingIds.contains(activity.id)
            ? LifesumImportConflict.exactId
            : existingDays.contains(
                _logicalDayKey(activity.date, dayStartOffsetMinutes),
              )
            ? LifesumImportConflict.occupiedLogicalDay
            : null;
        return LifesumCandidateReview<LifesumActivityCandidate>(
          candidate: candidate,
          conflict: conflict,
        );
      }).toList(),
    );
  }

  final LifesumActivityParseResult parseResult;
  final List<LifesumCandidateReview<LifesumActivityCandidate>> reviews;

  int get candidateCount => reviews.length;
  int get readyToAddCount =>
      reviews.where((review) => !review.hasConflict).length;
  int get exactIdConflictCount => reviews
      .where((review) => review.conflict == LifesumImportConflict.exactId)
      .length;
  int get occupiedDayConflictCount => reviews
      .where(
        (review) => review.conflict == LifesumImportConflict.occupiedLogicalDay,
      )
      .length;
  int get existingConflictCount =>
      exactIdConflictCount + occupiedDayConflictCount;
  int get blockingIssueCount => parseResult.blockingIssueCount;
  int get warningCount => parseResult.warningCount;

  List<LifesumActivityCandidate> get candidatesToAdd =>
      List<LifesumActivityCandidate>.unmodifiable(
        reviews
            .where((review) => !review.hasConflict)
            .map((review) => review.candidate),
      );

  DateTime? get earliestCandidateDay => parseResult.trackedDays.isEmpty
      ? null
      : parseResult.trackedDays.first.day;
  DateTime? get latestCandidateDay =>
      parseResult.trackedDays.isEmpty ? null : parseResult.trackedDays.last.day;
}

class LifesumRecipeImportPreview {
  LifesumRecipeImportPreview._({
    required this.parseResult,
    required List<LifesumCandidateReview<LifesumRecipeCandidate>> reviews,
  }) : reviews =
           List<LifesumCandidateReview<LifesumRecipeCandidate>>.unmodifiable(
             reviews,
           );

  factory LifesumRecipeImportPreview.fromParseResult(
    LifesumRecipeParseResult result, {
    Iterable<RecipeEntity> existingRecipes = const <RecipeEntity>[],
  }) {
    final existing = existingRecipes.toList(growable: false);
    final existingIds = existing.map((entry) => entry.id).toSet();
    final existingNames = existing
        .map((entry) => _normalizeName(entry.name))
        .toSet();
    return LifesumRecipeImportPreview._(
      parseResult: result,
      reviews: result.candidates.map((candidate) {
        final conflict = existingIds.contains(candidate.id)
            ? LifesumImportConflict.exactId
            : existingNames.contains(_normalizeName(candidate.title))
            ? LifesumImportConflict.normalizedName
            : null;
        return LifesumCandidateReview<LifesumRecipeCandidate>(
          candidate: candidate,
          conflict: conflict,
        );
      }).toList(),
    );
  }

  final LifesumRecipeParseResult parseResult;
  final List<LifesumCandidateReview<LifesumRecipeCandidate>> reviews;

  int get candidateCount => reviews.length;
  int get exactIdConflictCount => reviews
      .where((review) => review.conflict == LifesumImportConflict.exactId)
      .length;
  int get normalizedNameConflictCount => reviews
      .where(
        (review) => review.conflict == LifesumImportConflict.normalizedName,
      )
      .length;
  int get existingConflictCount =>
      exactIdConflictCount + normalizedNameConflictCount;
  int get blockingIssueCount => parseResult.blockingIssueCount;
  int get warningCount => parseResult.warningCount;

  /// Stable cannot honestly create current RecipeEntity records from these
  /// snapshots until a no-fabrication snapshot persistence model exists.
  int get snapshotPersistenceRequiredCount => candidateCount;
  int get readyToAddCount => 0;

  DateTime? get earliestCandidateDate {
    if (reviews.isEmpty) return null;
    final dates = reviews.map((review) => review.candidate.createdAt).toList()
      ..sort();
    return dates.first;
  }

  DateTime? get latestCandidateDate {
    if (reviews.isEmpty) return null;
    final dates = reviews.map((review) => review.candidate.createdAt).toList()
      ..sort();
    return dates.last;
  }
}

/// Cross-domain, read-only interpretation of selected Lifesum CSVs.
///
/// This object never opens repositories and never writes. It drops the raw
/// CSV strings after parsing, retains only typed candidates, and applies the
/// conservative default of keeping any Stable logical day already in use.
class LifesumImportPreview {
  LifesumImportPreview._({
    required this.inspection,
    required Set<LifesumExportSection> requestedSections,
    required Set<LifesumExportSection> loadedSections,
    required Set<LifesumExportSection> unavailableSections,
    required this.food,
    required this.activity,
    required this.measurements,
    required this.recipes,
    required this.estimatedWater,
    required this.earliestArchiveCandidateDate,
    required this.latestArchiveCandidateDate,
  }) : requestedSections = Set<LifesumExportSection>.unmodifiable(
         requestedSections,
       ),
       loadedSections = Set<LifesumExportSection>.unmodifiable(loadedSections),
       unavailableSections = Set<LifesumExportSection>.unmodifiable(
         unavailableSections,
       );

  factory LifesumImportPreview.fromSelection(
    LifesumArchiveCsvSelection selection, {
    Iterable<IntakeEntity> existingIntakes = const <IntakeEntity>[],
    Iterable<UserActivityEntity> existingActivities =
        const <UserActivityEntity>[],
    Iterable<WeightLogEntity> existingWeights = const <WeightLogEntity>[],
    Iterable<BodyMeasurementLogEntity> existingBodyMeasurements =
        const <BodyMeasurementLogEntity>[],
    Iterable<RecipeEntity> existingRecipes = const <RecipeEntity>[],
    Iterable<WaterIntakeEntity> existingWaterEntries =
        const <WaterIntakeEntity>[],
    int dayStartOffsetMinutes = 0,
    int estimatedWaterAmountPerDayMl = 2000,
  }) {
    final foodCsv = selection[LifesumExportSection.food];
    final food = foodCsv == null
        ? null
        : LifesumFoodImportPreview.fromParseResult(
            LifesumFoodParser.parse(
              foodCsv,
              dayStartOffsetMinutes: dayStartOffsetMinutes,
            ),
            existingIntakes: existingIntakes,
            dayStartOffsetMinutes: dayStartOffsetMinutes,
          );

    final activityCsv = selection[LifesumExportSection.exercise];
    final activity = activityCsv == null
        ? null
        : LifesumActivityImportPreview.fromParseResult(
            LifesumActivityParser.parse(
              activityCsv,
              dayStartOffsetMinutes: dayStartOffsetMinutes,
            ),
            existingActivities: existingActivities,
            dayStartOffsetMinutes: dayStartOffsetMinutes,
          );

    const measurementSections = <LifesumExportSection>{
      LifesumExportSection.weighIns,
      LifesumExportSection.bodyMeasures,
      LifesumExportSection.bodyFat,
    };
    final hasMeasurementCsv = selection.loadedSections.any(
      measurementSections.contains,
    );
    final measurements = hasMeasurementCsv
        ? LifesumMeasurementPreview.fromParseResult(
            LifesumMeasurementParser.parse(
              weighInsCsv: selection[LifesumExportSection.weighIns],
              bodyMeasuresCsv: selection[LifesumExportSection.bodyMeasures],
              bodyFatCsv: selection[LifesumExportSection.bodyFat],
            ),
            existingWeights: existingWeights,
            existingBodyMeasurements: existingBodyMeasurements,
          )
        : null;

    final recipeCsv = selection[LifesumExportSection.recipes];
    final recipes = recipeCsv == null
        ? null
        : LifesumRecipeImportPreview.fromParseResult(
            LifesumRecipeParser.parse(recipeCsv),
            existingRecipes: existingRecipes,
          );

    final trackedDays = food?.parseResult.trackedDays;
    final estimatedWater = trackedDays == null || trackedDays.isEmpty
        ? null
        : LifesumEstimatedWaterPlan.build(
            startDay: trackedDays.first.day,
            endDay: trackedDays.last.day,
            amountPerDayMl: estimatedWaterAmountPerDayMl,
            dayStartOffsetMinutes: dayStartOffsetMinutes,
            existingEntries: existingWaterEntries,
          );

    final candidateDates = <DateTime>[
      ...?food?.parseResult.trackedDays.map((entry) => entry.day),
      ...?activity?.parseResult.trackedDays.map((entry) => entry.day),
      ...?recipes?.reviews.map((review) => review.candidate.createdAt),
    ];
    final measurementEarliest = measurements?.earliestCandidateDate;
    final measurementLatest = measurements?.latestCandidateDate;
    if (measurementEarliest != null) candidateDates.add(measurementEarliest);
    if (measurementLatest != null) candidateDates.add(measurementLatest);
    candidateDates.sort();

    return LifesumImportPreview._(
      inspection: selection.inspection,
      requestedSections: selection.requestedSections,
      loadedSections: selection.loadedSections,
      unavailableSections: selection.unavailableSections,
      food: food,
      activity: activity,
      measurements: measurements,
      recipes: recipes,
      estimatedWater: estimatedWater,
      earliestArchiveCandidateDate: candidateDates.isEmpty
          ? null
          : candidateDates.first,
      latestArchiveCandidateDate: candidateDates.isEmpty
          ? null
          : candidateDates.last,
    );
  }

  final LifesumArchiveInspection inspection;
  final Set<LifesumExportSection> requestedSections;
  final Set<LifesumExportSection> loadedSections;
  final Set<LifesumExportSection> unavailableSections;
  final LifesumFoodImportPreview? food;
  final LifesumActivityImportPreview? activity;
  final LifesumMeasurementPreview? measurements;
  final LifesumRecipeImportPreview? recipes;
  final LifesumEstimatedWaterPlan? estimatedWater;
  final DateTime? earliestArchiveCandidateDate;
  final DateTime? latestArchiveCandidateDate;

  int get archiveCandidateCount =>
      (food?.candidateCount ?? 0) +
      (activity?.candidateCount ?? 0) +
      (measurements?.candidateCount ?? 0) +
      (recipes?.candidateCount ?? 0);

  int get readyToAddCount =>
      (food?.readyToAddCount ?? 0) +
      (activity?.readyToAddCount ?? 0) +
      (measurements?.readyToAddCount ?? 0);

  int get existingConflictCount =>
      (food?.existingConflictCount ?? 0) +
      (activity?.existingConflictCount ?? 0) +
      (measurements?.existingConflictCount ?? 0) +
      (recipes?.existingConflictCount ?? 0);

  int get blockingIssueCount =>
      (food?.blockingIssueCount ?? 0) +
      (activity?.blockingIssueCount ?? 0) +
      (measurements?.blockingIssueCount ?? 0) +
      (recipes?.blockingIssueCount ?? 0);

  int get warningCount =>
      (food?.warningCount ?? 0) +
      (activity?.warningCount ?? 0) +
      (measurements?.warningCount ?? 0) +
      (recipes?.warningCount ?? 0);

  int get estimatedWaterCandidateCount =>
      estimatedWater?.candidateDayCount ?? 0;

  int get recipeSnapshotPersistenceRequiredCount =>
      recipes?.snapshotPersistenceRequiredCount ?? 0;
}

int _logicalDayKey(DateTime dateTime, int dayStartOffsetMinutes) =>
    _calendarDayKey(
      DayBoundaryCalc.logicalDayOfMinutes(dateTime, dayStartOffsetMinutes),
    );

int _calendarDayKey(DateTime date) =>
    date.year * 10000 + date.month * 100 + date.day;

String _normalizeName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
