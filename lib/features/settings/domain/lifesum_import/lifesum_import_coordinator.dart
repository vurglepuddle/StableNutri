import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_existing_history_loader.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_executor.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_journal.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_manifest.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_preview.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_tracked_day_plan.dart';

abstract interface class LifesumArchivePicker {
  Future<String?> pickArchivePath();
}

class LifesumImportSettingsSnapshot {
  LifesumImportSettingsSnapshot({
    required this.dayStartOffsetMinutes,
    required this.historicalGoals,
  }) {
    if (dayStartOffsetMinutes < 0 || dayStartOffsetMinutes >= 24 * 60) {
      throw ArgumentError.value(dayStartOffsetMinutes, 'dayStartOffsetMinutes');
    }
  }

  final int dayStartOffsetMinutes;
  final LifesumHistoricalGoalSnapshot historicalGoals;
}

enum LifesumImportCoordinatorFailure {
  invalidArchiveSelection,
  activeProfileChanged,
  previewChanged,
  alreadyConfirmed,
  foreignPreparation,
}

class LifesumImportCoordinatorException implements Exception {
  const LifesumImportCoordinatorException(this.failure);

  final LifesumImportCoordinatorFailure failure;

  @override
  String toString() => 'Lifesum import coordination error: $failure';
}

/// One read-only preview captured for a single active-profile generation.
///
/// The source path and generation token stay private and in memory. Nothing
/// here persists archive data, and only [LifesumImportCoordinator.confirm]
/// can cross the mutation boundary.
class LifesumImportPreparation {
  LifesumImportPreparation._({
    required this.preview,
    required this.historicalGoals,
    required this.profileId,
    required String archivePath,
    required int profileGeneration,
    required String reviewFingerprint,
    required Object owner,
  }) : _archivePath = archivePath,
       _profileGeneration = profileGeneration,
       _reviewFingerprint = reviewFingerprint,
       _owner = owner;

  final LifesumImportPreview preview;
  final LifesumHistoricalGoalSnapshot historicalGoals;
  final String profileId;
  final String _archivePath;
  final int _profileGeneration;
  final String _reviewFingerprint;
  final Object _owner;
  bool _confirmationStarted = false;

  bool get confirmationStarted => _confirmationStarted;

  int operationCountFor(LifesumImportSelection selection) =>
      _completeManifest(preview, historicalGoals, selection).operationCount;
}

/// Coordinates archive selection, read-only preview, stale-preview
/// revalidation, and the one explicit confirmation boundary.
class LifesumImportCoordinator {
  LifesumImportCoordinator({
    required HiveDBProvider database,
    required LifesumArchivePicker picker,
    required LifesumExistingHistoryLoader historyLoader,
    required Future<LifesumImportSettingsSnapshot> Function() loadSettings,
    required LifesumImportExecutor Function() createExecutor,
    LifesumArchiveReader archiveReader = const LifesumArchiveReader(),
  }) : _database = database,
       _picker = picker,
       _historyLoader = historyLoader,
       _loadSettings = loadSettings,
       _createExecutor = createExecutor,
       _archiveReader = archiveReader;

  final HiveDBProvider _database;
  final LifesumArchivePicker _picker;
  final LifesumExistingHistoryLoader _historyLoader;
  final Future<LifesumImportSettingsSnapshot> Function() _loadSettings;
  final LifesumImportExecutor Function() _createExecutor;
  final LifesumArchiveReader _archiveReader;
  final Object _owner = Object();

  /// Returns null only when the platform picker was cancelled.
  Future<LifesumImportPreparation?> chooseArchive() async {
    final path = await _picker.pickArchivePath();
    if (path == null) return null;
    return prepareArchivePath(path);
  }

  /// Path-based entry point retained for deterministic tests and future
  /// platform integrations. It performs no Stable writes.
  Future<LifesumImportPreparation> prepareArchivePath(String path) async {
    if (path.trim().isEmpty) {
      throw const LifesumImportCoordinatorException(
        LifesumImportCoordinatorFailure.invalidArchiveSelection,
      );
    }
    final captured = await _capture(path);
    return LifesumImportPreparation._(
      preview: captured.preview,
      historicalGoals: captured.settings.historicalGoals,
      profileId: captured.profileId,
      archivePath: path,
      profileGeneration: captured.profileGeneration,
      reviewFingerprint: captured.reviewFingerprint,
      owner: _owner,
    );
  }

  /// Re-reads the archive and conflict inputs before executing. Any changed
  /// file, profile, goal, day boundary, or relevant Stable history forces a
  /// fresh preview instead of silently changing the confirmed operation set.
  Future<LifesumImportJournal> confirm(
    LifesumImportPreparation preparation, {
    LifesumImportSelection selection = const LifesumImportSelection(),
  }) async {
    _beginConfirmation(preparation);
    _requireProfile(preparation);

    final expectedManifest = _completeManifest(
      preparation.preview,
      preparation.historicalGoals,
      selection,
    );
    final current = await _capture(preparation._archivePath);
    _requireProfile(preparation);
    final currentManifest = _completeManifest(
      current.preview,
      current.settings.historicalGoals,
      selection,
    );
    if (current.reviewFingerprint != preparation._reviewFingerprint ||
        currentManifest.manifestId != expectedManifest.manifestId) {
      throw const LifesumImportCoordinatorException(
        LifesumImportCoordinatorFailure.previewChanged,
      );
    }

    _requireProfile(preparation);
    return _createExecutor().execute(currentManifest);
  }

  Future<_CapturedImport> _capture(String path) async {
    final profileId = _database.activeProfileId;
    final profileGeneration = _database.activeProfileGeneration;
    final archiveSelection = _archiveReader.readCsvSectionsPath(
      path,
      LifesumExportSection.values.toSet(),
    );
    if (archiveSelection.loadedSections.isEmpty) {
      throw const LifesumImportCoordinatorException(
        LifesumImportCoordinatorFailure.invalidArchiveSelection,
      );
    }
    final results = await Future.wait<Object>(<Future<Object>>[
      _historyLoader.load(),
      _loadSettings(),
    ]);
    if (_database.activeProfileId != profileId ||
        _database.activeProfileGeneration != profileGeneration) {
      throw const LifesumImportCoordinatorException(
        LifesumImportCoordinatorFailure.activeProfileChanged,
      );
    }
    final history = results[0] as LifesumExistingHistory;
    final settings = results[1] as LifesumImportSettingsSnapshot;
    if (history.profileId != profileId) {
      throw const LifesumImportCoordinatorException(
        LifesumImportCoordinatorFailure.activeProfileChanged,
      );
    }
    final preview = history.buildPreview(
      archiveSelection,
      dayStartOffsetMinutes: settings.dayStartOffsetMinutes,
    );
    return _CapturedImport(
      profileId: profileId,
      profileGeneration: profileGeneration,
      preview: preview,
      settings: settings,
      reviewFingerprint: _reviewFingerprint(preview, settings.historicalGoals),
    );
  }

  void _beginConfirmation(LifesumImportPreparation preparation) {
    if (!identical(preparation._owner, _owner)) {
      throw const LifesumImportCoordinatorException(
        LifesumImportCoordinatorFailure.foreignPreparation,
      );
    }
    if (preparation._confirmationStarted) {
      throw const LifesumImportCoordinatorException(
        LifesumImportCoordinatorFailure.alreadyConfirmed,
      );
    }
    preparation._confirmationStarted = true;
  }

  void _requireProfile(LifesumImportPreparation preparation) {
    if (_database.activeProfileId != preparation.profileId ||
        _database.activeProfileGeneration != preparation._profileGeneration) {
      throw const LifesumImportCoordinatorException(
        LifesumImportCoordinatorFailure.activeProfileChanged,
      );
    }
  }
}

class _CapturedImport {
  const _CapturedImport({
    required this.profileId,
    required this.profileGeneration,
    required this.preview,
    required this.settings,
    required this.reviewFingerprint,
  });

  final String profileId;
  final int profileGeneration;
  final LifesumImportPreview preview;
  final LifesumImportSettingsSnapshot settings;
  final String reviewFingerprint;
}

LifesumImportManifest _completeManifest(
  LifesumImportPreview preview,
  LifesumHistoricalGoalSnapshot goals,
  LifesumImportSelection selection,
) {
  final primary = LifesumImportManifest.fromPreview(
    preview,
    selection: selection,
  );
  return LifesumTrackedDayPlan.fromManifest(
    primary,
    goals: goals,
  ).completeManifest(primary);
}

String _reviewFingerprint(
  LifesumImportPreview preview,
  LifesumHistoricalGoalSnapshot goals,
) {
  final allSupportedManifest = _completeManifest(
    preview,
    goals,
    const LifesumImportSelection(includeEstimatedWater: true),
  );
  final food = preview.food;
  final activity = preview.activity;
  final measurements = preview.measurements;
  final recipes = preview.recipes;
  final water = preview.estimatedWater;
  return <String>[
    allSupportedManifest.manifestId,
    ...preview.loadedSections.map((section) => section.name).toList()..sort(),
    '|',
    ...preview.unavailableSections.map((section) => section.name).toList()
      ..sort(),
    '|archive:${preview.inspection.archiveSizeBytes}:'
        '${preview.inspection.fileCount}:'
        '${preview.inspection.totalUncompressedSizeBytes}:'
        '${preview.inspection.ignoredFileCount}:'
        '${preview.inspection.ignoredUncompressedSizeBytes}',
    'food:${food?.candidateCount ?? 0}:${food?.readyToAddCount ?? 0}:'
        '${food?.existingConflictCount ?? 0}:${food?.blockingIssueCount ?? 0}:'
        '${food?.warningCount ?? 0}',
    'activity:${activity?.candidateCount ?? 0}:'
        '${activity?.readyToAddCount ?? 0}:'
        '${activity?.existingConflictCount ?? 0}:'
        '${activity?.blockingIssueCount ?? 0}:${activity?.warningCount ?? 0}',
    'measurements:${measurements?.candidateCount ?? 0}:'
        '${measurements?.readyToAddCount ?? 0}:'
        '${measurements?.existingConflictCount ?? 0}:'
        '${measurements?.blockingIssueCount ?? 0}:'
        '${measurements?.warningCount ?? 0}',
    'recipes:${recipes?.candidateCount ?? 0}:'
        '${recipes?.existingConflictCount ?? 0}:'
        '${recipes?.blockingIssueCount ?? 0}:${recipes?.warningCount ?? 0}',
    ...?recipes?.reviews.map((review) => review.candidate.id),
    'water:${water?.candidateDayCount ?? 0}:${water?.existingDayCount ?? 0}',
  ].join('\u001f');
}
