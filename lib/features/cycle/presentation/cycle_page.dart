import 'package:flutter/material.dart';
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

class CycleTrends extends StatelessWidget {
  const CycleTrends({super.key});
  @override
  Widget build(BuildContext context) {
    if (!locator.isRegistered<CycleRepository>()) {
      return const SizedBox.shrink();
    }
    final repo = locator<CycleRepository>();
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final data = repo.data;
        if (!data.enabled) return const SizedBox.shrink();
        final s = S.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: CycleCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.cycleHistory,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(s.cycleAverage),
                Text(
                  s.cycleAveragesDays(
                    data.averageCycle.toStringAsFixed(1),
                    data.averagePeriod.toStringAsFixed(1),
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  s.cycleObservationCounts(
                    data.cycleLengths.length.clamp(0, 6),
                    data.periodLengths.length.clamp(0, 6),
                  ),
                ),
                Text(
                  s.cycleBasedOn,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (data.records.isEmpty) Text(s.cycleNoHistory),
                for (final row in data.sorted.reversed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_date(context, row.start)),
                    subtitle: Text(
                      row.end == null
                          ? s.cycleOngoing
                          : _date(context, row.end!),
                    ),
                    onTap: () => editPeriod(context, repo, record: row),
                    trailing: Semantics(
                      identifier: 'cycle-delete-record',
                      child: IconButton(
                        tooltip: s.cycleDelete,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final generation = repo.db.activeProfileGeneration;
                          final remove = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(s.cycleDelete),
                              content: Text(s.cycleDeleteBody),
                              actions: [
                                _CycleDialogButton(
                                  identifier: 'cycle-delete-cancel',
                                  onPressed: () =>
                                      Navigator.pop(context, false),
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
                          if (remove == true && context.mounted) {
                            await _save(
                              context,
                              repo,
                              data.copyWith(
                                records: data.records
                                    .where((r) => r.id != row.id)
                                    .toList(),
                                clearExpected: true,
                              ),
                              generation,
                            );
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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
