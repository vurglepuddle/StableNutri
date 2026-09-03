import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_preview.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_measurement_preview.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/lifesum_import_bloc.dart';
import 'package:opennutritracker/features/trends/presentation/bloc/trends_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

class LifesumImportScreen extends StatefulWidget {
  const LifesumImportScreen({super.key, this.bloc, this.onImported});

  final LifesumImportBloc? bloc;
  final VoidCallback? onImported;

  @override
  State<LifesumImportScreen> createState() => _LifesumImportScreenState();
}

class _LifesumImportScreenState extends State<LifesumImportScreen> {
  late final LifesumImportBloc _bloc;
  late final bool _ownsBloc;

  @override
  void initState() {
    super.initState();
    _ownsBloc = widget.bloc == null;
    _bloc = widget.bloc ?? locator<LifesumImportBloc>();
  }

  @override
  void dispose() {
    if (_ownsBloc) _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LifesumImportBloc, LifesumImportState>(
      bloc: _bloc,
      listener: (context, state) {
        if (state is LifesumImportSuccess) {
          final callback = widget.onImported;
          if (callback != null) {
            callback();
          } else {
            _refreshAppState();
          }
        }
      },
      builder: (context, state) => PopScope(
        canPop: state is! LifesumImportApplying,
        child: Scaffold(
          appBar: AppBar(title: Text(S.of(context).lifesumImportTitle)),
          body: SafeArea(child: _buildBody(context, state)),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, LifesumImportState state) {
    return switch (state) {
      LifesumImportInitial() => _ChooseArchiveView(
        onChoose: () => _bloc.add(const ChooseLifesumArchiveEvent()),
      ),
      LifesumImportLoading() => _ProgressView(
        label: S.of(context).lifesumImportReading,
      ),
      LifesumImportReady() => _ReviewView(
        state: state,
        onSetCategory: (category, included) => _bloc.add(
          SetLifesumImportCategoryEvent(category: category, included: included),
        ),
        onChooseAgain: () => _bloc.add(const ChooseLifesumArchiveEvent()),
        onConfirm: () => _confirmImport(context, state),
      ),
      LifesumImportApplying() => _ProgressView(
        label: S.of(context).lifesumImportApplying,
      ),
      LifesumImportSuccess() => _SuccessView(
        addedCount: state.addedCount,
        keptCount: state.keptCount,
        onDone: () => Navigator.of(context).pop(),
      ),
      LifesumImportError() => _ErrorView(
        kind: state.kind,
        onChooseAgain: () => _bloc.add(const ChooseLifesumArchiveEvent()),
      ),
    };
  }

  Future<void> _confirmImport(
    BuildContext context,
    LifesumImportReady state,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).lifesumImportConfirmTitle),
        content: Text(
          S.of(context).lifesumImportConfirmBody(state.selectedOperationCount),
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey('lifesum-cancel-import'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(S.of(context).dialogCancelLabel),
          ),
          FilledButton(
            key: const ValueKey('lifesum-confirm-import'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(S.of(context).lifesumImportConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _bloc.add(const ConfirmLifesumImportEvent());
    }
  }

  void _refreshAppState() {
    locator<HomeBloc>().add(const LoadItemsEvent());
    locator<DiaryBloc>().add(const LoadDiaryYearEvent());
    locator<CalendarDayBloc>().add(RefreshCalendarDayEvent());
    locator<TrendsBloc>().add(const LoadTrendsEvent());
    locator<ProfileBloc>().add(LoadProfileEvent());
  }
}

class _ChooseArchiveView extends StatelessWidget {
  const _ChooseArchiveView({required this.onChoose});

  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: <Widget>[
        Text(
          S.of(context).lifesumImportChooseHeading,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          S.of(context).lifesumImportChooseIntro,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.primary, width: 1.5),
          ),
          child: Column(
            children: <Widget>[
              Icon(Icons.archive_outlined, size: 38, color: colors.primary),
              const SizedBox(height: 12),
              Text(
                S.of(context).lifesumImportArchiveLabel,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                S.of(context).lifesumImportArchiveSupport,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const ValueKey('lifesum-choose-archive'),
                onPressed: onChoose,
                icon: const Icon(Icons.file_open_outlined),
                label: Text(S.of(context).lifesumImportChooseZip),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _PrivacyNote(),
      ],
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({
    required this.state,
    required this.onSetCategory,
    required this.onChooseAgain,
    required this.onConfirm,
  });

  final LifesumImportReady state;
  final void Function(LifesumImportCategory category, bool included)
  onSetCategory;
  final VoidCallback onChooseAgain;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final preview = state.preparation.preview;
    final food = preview.food;
    final activity = preview.activity;
    final measurements = preview.measurements;
    final recipes = preview.recipes;
    final water = preview.estimatedWater;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: <Widget>[
        Text(
          S.of(context).lifesumImportReviewHeading,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          _dateRangeCopy(context, preview),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        _ReviewSummary(preview: preview),
        const SizedBox(height: 14),
        if (food != null)
          _CategoryCard(
            key: const ValueKey('lifesum-food-category'),
            icon: Icons.restaurant_outlined,
            title: S.of(context).lifesumImportFoodDiary,
            selected: state.selection.includeFood,
            addCount: food.readyToAddCount,
            keepCount: food.existingConflictCount,
            warningCount: food.warningCount + food.blockingIssueCount,
            onChanged: (value) =>
                onSetCategory(LifesumImportCategory.food, value),
          ),
        if (activity != null)
          _CategoryCard(
            key: const ValueKey('lifesum-activity-category'),
            icon: Icons.directions_walk_outlined,
            title: S.of(context).lifesumImportActivities,
            selected: state.selection.includeActivity,
            addCount: activity.readyToAddCount,
            keepCount: activity.existingConflictCount,
            warningCount: activity.warningCount + activity.blockingIssueCount,
            detail: activity.parseResult.ignoredHealthConnectCount == 0
                ? null
                : S
                      .of(context)
                      .lifesumImportHealthConnectIgnored(
                        activity.parseResult.ignoredHealthConnectCount,
                      ),
            onChanged: (value) =>
                onSetCategory(LifesumImportCategory.activity, value),
          ),
        if (measurements != null)
          _MeasurementCard(
            preview: measurements,
            includeWeight: state.selection.includeWeights,
            includeBodyMeasurements: state.selection.includeBodyMeasurements,
            onSetCategory: onSetCategory,
          ),
        if (water != null)
          _CategoryCard(
            key: const ValueKey('lifesum-water-category'),
            icon: Icons.water_drop_outlined,
            title: S.of(context).lifesumImportWaterTitle,
            selected: state.selection.includeEstimatedWater,
            addCount: water.candidateDayCount,
            keepCount: water.existingDayCount,
            warningCount: 0,
            detail: S
                .of(context)
                .lifesumImportWaterDetail(
                  water.amountPerDayMl,
                  _date(water.startDay),
                  _date(water.endDay),
                ),
            onChanged: (value) =>
                onSetCategory(LifesumImportCategory.estimatedWater, value),
          ),
        if (recipes != null)
          _UnavailableCategoryCard(
            icon: Icons.menu_book_outlined,
            title: S.of(context).recipesLabel,
            detail: S
                .of(context)
                .lifesumImportRecipesDetail(recipes.candidateCount),
          ),
        _UnavailableCategoryCard(
          icon: Icons.favorite_border,
          title: S.of(context).libraryFavoritesLabel,
          detail: S.of(context).lifesumImportFavoritesDetail,
        ),
        const SizedBox(height: 6),
        const _PrivacyNote(),
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const ValueKey('lifesum-review-import'),
          onPressed: state.selectedOperationCount == 0 ? null : onConfirm,
          icon: const Icon(Icons.download_done_outlined),
          label: Text(S.of(context).lifesumImportSelectedAction),
        ),
        TextButton(
          onPressed: onChooseAgain,
          child: Text(S.of(context).lifesumImportChooseAgain),
        ),
      ],
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.preview});

  final LifesumImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 10,
        children: <Widget>[
          _SummaryValue(
            label: S.of(context).lifesumImportReady,
            value: preview.readyToAddCount,
          ),
          _SummaryValue(
            label: S.of(context).lifesumImportKeepExisting,
            value: preview.existingConflictCount,
          ),
          _SummaryValue(
            label: S.of(context).lifesumImportWarnings,
            value: preview.warningCount + preview.blockingIssueCount,
          ),
          _SummaryValue(
            label: S.of(context).lifesumImportFilesIgnored,
            value: preview.inspection.ignoredFileCount,
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value.toString(),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.addCount,
    required this.keepCount,
    required this.warningCount,
    required this.onChanged,
    this.detail,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final int addCount;
  final int keepCount;
  final int warningCount;
  final ValueChanged<bool> onChanged;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        value: selected,
        onChanged: onChanged,
        secondary: CircleAvatar(
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimaryContainer,
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            <String>[
              S.of(context).lifesumImportToAdd(addCount),
              if (keepCount > 0)
                S.of(context).lifesumImportExistingKept(keepCount),
              if (warningCount > 0)
                S.of(context).lifesumImportWarningCount(warningCount),
              ?detail,
            ].join(' · '),
          ),
        ),
      ),
    );
  }
}

class _MeasurementCard extends StatelessWidget {
  const _MeasurementCard({
    required this.preview,
    required this.includeWeight,
    required this.includeBodyMeasurements,
    required this.onSetCategory,
  });

  final LifesumMeasurementPreview preview;
  final bool includeWeight;
  final bool includeBodyMeasurements;
  final void Function(LifesumImportCategory category, bool included)
  onSetCategory;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('lifesum-measurements-category'),
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          SwitchListTile(
            value: includeWeight,
            onChanged: (value) =>
                onSetCategory(LifesumImportCategory.weight, value),
            secondary: const Icon(Icons.monitor_weight_outlined),
            title: Text(
              S.of(context).lifesumImportWeightHistory,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${S.of(context).lifesumImportToAdd(preview.weightsToAdd.length)} '
              '· ${S.of(context).lifesumImportExistingKept(preview.existingWeightConflictCount)}',
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: includeBodyMeasurements,
            onChanged: (value) =>
                onSetCategory(LifesumImportCategory.bodyMeasurements, value),
            secondary: const Icon(Icons.straighten_outlined),
            title: Text(
              S.of(context).lifesumImportBodyMeasurements,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              <String>[
                S
                    .of(context)
                    .lifesumImportToAdd(preview.bodyMeasurementsToAdd.length),
                S
                    .of(context)
                    .lifesumImportExistingKept(
                      preview.existingBodyMeasurementConflictCount,
                    ),
                if (preview.warningCount + preview.blockingIssueCount > 0)
                  S
                      .of(context)
                      .lifesumImportWarningCount(
                        preview.warningCount + preview.blockingIssueCount,
                      ),
              ].join(' · '),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnavailableCategoryCard extends StatelessWidget {
  const _UnavailableCategoryCard({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      enabled: false,
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              S.of(context).lifesumImportNotImported,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(detail),
          ],
        ),
      ),
    ),
  );
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(
        Icons.lock_outline,
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(S.of(context).lifesumImportPrivacy)),
    ],
  );
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({
    required this.addedCount,
    required this.keptCount,
    required this.onDone,
  });

  final int addedCount;
  final int keptCount;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.check_circle_outline,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            S.of(context).lifesumImportSuccessTitle,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            keptCount == 0
                ? S.of(context).lifesumImportSuccessBody(addedCount)
                : S
                      .of(context)
                      .lifesumImportSuccessBodyWithKept(addedCount, keptCount),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onDone,
            child: Text(S.of(context).lifesumImportDone),
          ),
        ],
      ),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.kind, required this.onChooseAgain});

  final LifesumImportErrorKind kind;
  final VoidCallback onChooseAgain;

  @override
  Widget build(BuildContext context) {
    final strings = S.of(context);
    final (title, detail) = switch (kind) {
      LifesumImportErrorKind.invalidArchive => (
        strings.lifesumImportInvalidTitle,
        strings.lifesumImportInvalidDetail,
      ),
      LifesumImportErrorKind.profileChanged => (
        strings.lifesumImportProfileChangedTitle,
        strings.lifesumImportProfileChangedDetail,
      ),
      LifesumImportErrorKind.previewChanged => (
        strings.lifesumImportPreviewChangedTitle,
        strings.lifesumImportPreviewChangedDetail,
      ),
      LifesumImportErrorKind.confirmationExpired => (
        strings.lifesumImportExpiredTitle,
        strings.lifesumImportExpiredDetail,
      ),
      LifesumImportErrorKind.rolledBack => (
        strings.lifesumImportRolledBackTitle,
        strings.lifesumImportRolledBackDetail,
      ),
      LifesumImportErrorKind.importFailed => (
        strings.lifesumImportFailedTitle,
        strings.lifesumImportFailedDetail,
      ),
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: 52,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: onChooseAgain,
              child: Text(strings.lifesumImportChooseAgain),
            ),
          ],
        ),
      ),
    );
  }
}

String _dateRangeCopy(BuildContext context, LifesumImportPreview preview) {
  final start = preview.earliestArchiveCandidateDate;
  final end = preview.latestArchiveCandidateDate;
  if (start == null || end == null) {
    return S.of(context).lifesumImportSupportedHistoryFound;
  }
  return S
      .of(context)
      .lifesumImportSupportedHistoryRange(_date(start), _date(end));
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
