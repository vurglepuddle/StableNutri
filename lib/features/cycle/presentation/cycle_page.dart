import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/cycle/presentation/cycle_card.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/cycle/data/cycle_repository.dart';
import 'package:opennutritracker/features/cycle/domain/cycle_data.dart';
import 'package:opennutritracker/features/cycle/presentation/cycle_calendar.dart';
import 'package:opennutritracker/features/cycle/presentation/cycle_forms.dart';
import 'package:opennutritracker/generated/l10n.dart';

String _date(BuildContext context, DateTime date) =>
    cycleDateLabel(context, date);

Future<void> _save(
  BuildContext context,
  CycleRepository repo,
  CycleData data,
  int generation,
) async {
  try {
    await repo.save(data, generation: generation);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(S.of(context).cycleSaveFailed)));
    }
  }
}

class CyclePage extends StatelessWidget {
  const CyclePage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = locator<CycleRepository>();
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final s = S.of(context);
        final data = repo.data;
        if (!data.enabled) return const SizedBox.shrink();
        final expected = data.expectedStart;
        final generation = repo.db.activeProfileGeneration;
        final today = cycleDate(DateTime.now());
        final text = Theme.of(context).textTheme;
        final ongoing = data.records
            .where((record) => record.end == null)
            .firstOrNull;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CycleCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.cycleEstimate, style: text.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    expected == null
                        ? s.cycleNoStart
                        : _date(context, expected),
                    style: expected == null
                        ? text.bodyLarge
                        : text.headlineSmall,
                  ),
                  if (expected != null && !expected.isAfter(today)) ...[
                    const SizedBox(height: 4),
                    Text(s.cycleUnconfirmed, style: text.bodySmall),
                  ],
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Semantics(
                        identifier: ongoing == null
                            ? 'cycle-started'
                            : 'cycle-edit-current',
                        child: FilledButton.icon(
                          icon: Icon(
                            ongoing == null
                                ? Icons.add_rounded
                                : Icons.edit_outlined,
                            size: 20,
                          ),
                          label: Text(
                            ongoing == null ? s.cycleStarted : s.cycleEdit,
                          ),
                          onPressed: () =>
                              editPeriod(context, repo, record: ongoing),
                        ),
                      ),
                      if (expected != null && ongoing == null)
                        _CycleDialogButton(
                          identifier: 'cycle-not-yet',
                          onPressed: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(s.cycleNotYetHint)),
                              ),
                          child: Text(s.cycleNotYet),
                        ),
                    ],
                  ),
                  if (expected != null)
                    _CycleDialogButton(
                      identifier: 'cycle-change-expected',
                      child: Text(s.cycleChangeExpected),
                      onPressed: () async {
                        final selected = await pickCycleDate(
                          context,
                          title: s.cycleChangeExpected,
                          data: data,
                          initialDate: expected.isAfter(today)
                              ? expected
                              : today,
                          firstDate: today,
                          lastDate: DateTime(today.year + 2),
                        );
                        if (selected != null && context.mounted) {
                          await _save(
                            context,
                            repo,
                            data.copyWith(expectedOverride: selected),
                            generation,
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CycleCard(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  CycleCalendar(
                    data: data,
                    initialDay: today,
                    firstDay: DateTime(1900),
                    // Forecasts repeat for as far as the user scrolls.
                    lastDay: DateTime(today.year + 5),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 8, 8, 12),
                    child: CycleCalendarLegend(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _CycleAverages(data: data),
            const SizedBox(height: 16),
            CycleCard(
              child: Column(
                children: [
                  _CycleSettingsRow(
                    identifier: 'cycle-backfill',
                    icon: Icons.playlist_add_rounded,
                    title: s.cycleAddPast,
                    onTap: () => editPeriod(context, repo, past: true),
                  ),
                  const Divider(height: 1),
                  _CycleSettingsRow(
                    identifier: 'cycle-setup',
                    icon: Icons.tune_rounded,
                    title: s.cycleSetup,
                    onTap: () async {
                      final result = await Navigator.of(context)
                          .push<CycleData>(
                            MaterialPageRoute(
                              builder: (_) => CycleSetupPage(data: data),
                            ),
                          );
                      if (result != null && context.mounted) {
                        await _save(context, repo, result, generation);
                      }
                    },
                  ),
                  const Divider(height: 1),
                  _CycleSettingsRow(
                    identifier: 'cycle-calendar',
                    icon: Icons.calendar_today_rounded,
                    title: s.cycleCalendar,
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed(NavigationOptions.diaryRoute),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CycleCard(
              child: Column(
                children: [
                  Semantics(
                    identifier: 'cycle-reminder-toggle',
                    child: SwitchListTile.adaptive(
                      title: Text(s.cycleReminder),
                      value: data.reminderEnabled,
                      onChanged: (enabled) async {
                        try {
                          if (enabled) {
                            await repo.notifications.initialize();
                            if (!await repo.notifications.requestPermission()) {
                              return;
                            }
                          }
                          if (context.mounted) {
                            await _save(
                              context,
                              repo,
                              data.copyWith(reminderEnabled: enabled),
                              generation,
                            );
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(s.cycleReminderFailed)),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  if (data.reminderEnabled) ...[
                    const Divider(height: 1),
                    _CycleSettingsRow(
                      identifier: 'cycle-reminder-time',
                      icon: Icons.schedule_rounded,
                      title: s.cycleReminderTime,
                      subtitle: TimeOfDay(
                        hour: data.reminderHour,
                        minute: data.reminderMinute,
                      ).format(context),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          cancelText: s.cycleCancel,
                          confirmText: s.buttonSaveLabel,
                          initialTime: TimeOfDay(
                            hour: data.reminderHour,
                            minute: data.reminderMinute,
                          ),
                        );
                        if (time != null && context.mounted) {
                          await _save(
                            context,
                            repo,
                            data.copyWith(
                              reminderHour: time.hour,
                              reminderMinute: time.minute,
                            ),
                            generation,
                          );
                        }
                      },
                    ),
                  ],
                  if (repo.reminderFailed)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(s.cycleReminderFailed),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _CycleHistory(
              key: const ValueKey('cycle-history'),
              repo: repo,
              data: data,
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _CycleSettingsRow extends StatelessWidget {
  final String identifier;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _CycleSettingsRow({
    required this.identifier,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    identifier: identifier,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.primary,
        size: 22,
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

Future<void> editPeriod(
  BuildContext context,
  CycleRepository repo, {
  PeriodRecord? record,
  bool past = false,
}) async {
  final generation = repo.db.activeProfileGeneration;
  final result = await Navigator.of(context).push<CycleData>(
    MaterialPageRoute(
      builder: (_) =>
          PeriodEditorPage(data: repo.data, record: record, past: past),
    ),
  );
  if (result != null && context.mounted) {
    await _save(context, repo, result, generation);
  }
}

/// Averages sit in a soft bubble below the calendar; the rules are one tap away.
class _CycleAverages extends StatelessWidget {
  final CycleData data;
  const _CycleAverages({required this.data});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final muted = theme.textTheme.bodySmall?.copyWith(color: palette.textMuted);
    final format = NumberFormat(
      '0.#',
      Localizations.localeOf(context).toString(),
    );
    Widget stat(String label, double days) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: format.format(days),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: palette.textStrong,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(
                text: ' ${s.cycleDaysUnit(days)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: muted),
      ],
    );
    return Semantics(
      identifier: 'cycle-averages',
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 8, 12),
        decoration: BoxDecoration(
          // Tinting the card surface keeps the sage clean on the warm canvas.
          color: Color.alphaBlend(
            cycleSage(context).withValues(alpha: 0.16),
            palette.surface,
          ),
          borderRadius: Dimens.borderRadiusXL,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 32,
              runSpacing: 16,
              children: [
                stat(s.cycleAverageInterval, data.averageCycle),
                stat(s.cycleAverageDuration, data.averagePeriod),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.cycleObservationCounts(
                          data.countedCycles.length,
                          data.periodLengths.length.clamp(0, 6),
                        ),
                        style: muted,
                      ),
                      if (data.unusualCycles > 0)
                        Text(
                          s.cycleUnusualLeftOut(data.unusualCycles),
                          style: muted,
                        ),
                    ],
                  ),
                ),
                Semantics(
                  identifier: 'cycle-averages-info',
                  child: IconButton(
                    tooltip: s.cycleAveragesInfo,
                    icon: Icon(
                      Icons.info_outline_rounded,
                      color: palette.textMuted,
                      size: 20,
                    ),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(s.cycleAveragesInfo),
                        content: Text(s.cycleBasedOn),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(s.dialogOKLabel),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// History stays out of the way until asked for; it can grow long.
class _CycleHistory extends StatefulWidget {
  final CycleRepository repo;
  final CycleData data;
  const _CycleHistory({super.key, required this.repo, required this.data});

  @override
  State<_CycleHistory> createState() => _CycleHistoryState();
}

class _CycleHistoryState extends State<_CycleHistory>
    with AutomaticKeepAliveClientMixin {
  var open = false;

  // An open list survives scrolling back up to the calendar.
  @override
  bool get wantKeepAlive => open;

  Future<void> _remove(PeriodRecord row) async {
    final s = S.of(context);
    final repo = widget.repo;
    final generation = repo.db.activeProfileGeneration;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.cycleDelete),
        content: Text(s.cycleDeleteBody),
        actions: [
          _CycleDialogButton(
            identifier: 'cycle-delete-cancel',
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cycleCancel),
          ),
          _CycleDialogButton(
            identifier: 'cycle-delete-confirm',
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.cycleRemove),
          ),
        ],
      ),
    );
    if (remove == true && mounted) {
      final data = repo.data;
      await _save(
        context,
        repo,
        data.copyWith(
          records: data.records.where((r) => r.id != row.id).toList(),
          clearExpected: true,
        ),
        generation,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = S.of(context);
    final data = widget.data;
    return CycleCard(
      child: Column(
        children: [
          Semantics(
            identifier: 'cycle-history-toggle',
            expanded: open,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: Icon(
                Icons.history_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
              title: Text(s.cycleHistory),
              trailing: AnimatedRotation(
                turns: open ? 0.25 : 0,
                duration: AppMotion.durationShort,
                curve: AppMotion.standard,
                child: const Icon(Icons.chevron_right_rounded),
              ),
              onTap: () => setState(() {
                open = !open;
                updateKeepAlive();
              }),
            ),
          ),
          AnimatedSize(
            duration: AppMotion.durationShort,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      const Divider(height: 1),
                      if (data.records.isEmpty)
                        ListTile(title: Text(s.cycleNoHistory)),
                      for (final row in data.sorted.reversed)
                        ListTile(
                          contentPadding: const EdgeInsets.only(
                            left: 16,
                            right: 4,
                          ),
                          title: Text(
                            row.end == null
                                ? '${_date(context, row.start)} · '
                                      '${s.cycleOngoing}'
                                : '${_date(context, row.start)} – '
                                      '${_date(context, row.end!)}',
                          ),
                          onTap: () =>
                              editPeriod(context, widget.repo, record: row),
                          trailing: Semantics(
                            identifier: 'cycle-delete-record',
                            child: IconButton(
                              tooltip: s.cycleDelete,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _remove(row),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CycleDialogButton extends StatelessWidget {
  final String identifier;
  final VoidCallback onPressed;
  final Widget child;
  const _CycleDialogButton({
    required this.identifier,
    required this.onPressed,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    identifier: identifier,
    child: TextButton(onPressed: onPressed, child: child),
  );
}
