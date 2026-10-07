import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/cycle/data/cycle_repository.dart';
import 'package:opennutritracker/features/cycle/domain/cycle_data.dart';
import 'package:opennutritracker/generated/l10n.dart';

String _date(BuildContext context, DateTime d) =>
    MaterialLocalizations.of(context).formatMediumDate(d);

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
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.cycleEstimate,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    expected == null
                        ? s.cycleNoStart
                        : _date(context, expected),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (expected != null && !expected.isAfter(today))
                    Text(s.cycleUnconfirmed),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _action(
                        'cycle-started',
                        s.cycleStarted,
                        () => editPeriod(context, repo),
                      ),
                      _action(
                        'cycle-not-yet',
                        s.cycleNotYet,
                        () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(s.cycleNotYetHint)),
                        ),
                      ),
                      _action(
                        'cycle-change-expected',
                        s.cycleChangeExpected,
                        () async {
                          final selected = await showDatePicker(
                            context: context,
                            initialDate:
                                expected != null && expected.isAfter(today)
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
                ],
              ),
            ),
            const SizedBox(height: 16),
            _action(
              'cycle-backfill',
              s.cycleAddPast,
              () => editPeriod(context, repo),
            ),
            _action('cycle-setup', s.cycleSetup, () => _setup(context, repo)),
            _action(
              'cycle-calendar',
              s.cycleCalendar,
              () =>
                  Navigator.of(context).pushNamed(NavigationOptions.diaryRoute),
            ),
            Semantics(
              identifier: 'cycle-reminder-toggle',
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(s.cycleReminder),
                value: data.reminderEnabled,
                onChanged: (enabled) async {
                  if (enabled) {
                    await repo.notifications.initialize();
                    if (!await repo.notifications.requestPermission()) return;
                  }
                  if (context.mounted) {
                    await _save(
                      context,
                      repo,
                      data.copyWith(reminderEnabled: enabled),
                      generation,
                    );
                  }
                },
              ),
            ),
            if (data.reminderEnabled)
              Semantics(
                identifier: 'cycle-reminder-time',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.cycleReminderTime),
                  trailing: Text(
                    TimeOfDay(
                      hour: data.reminderHour,
                      minute: data.reminderMinute,
                    ).format(context),
                  ),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
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
              ),
            if (repo.reminderFailed) Text(s.cycleReminderFailed),
            if (data.records.any((r) => r.end == null)) ...[
              const SizedBox(height: 16),
              _action(
                'cycle-edit-current',
                s.cycleEdit,
                () => editPeriod(
                  context,
                  repo,
                  record: data.records.firstWhere((r) => r.end == null),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _action(String id, String label, VoidCallback action) => Semantics(
    identifier: id,
    child: TextButton(onPressed: action, child: Text(label)),
  );

  Future<void> _setup(BuildContext context, CycleRepository repo) async {
    final data = repo.data;
    final generation = repo.db.activeProfileGeneration;
    final cycle = TextEditingController(text: '${data.guessedCycleDays}');
    final period = TextEditingController(text: '${data.guessedPeriodDays}');
    var start = data.guessedStart;
    String? error;
    final s = S.of(context);
    final result = await showDialog<CycleData>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(s.cycleSetup),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  identifier: 'cycle-estimate-length',
                  child: TextField(
                    controller: cycle,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: s.cycleLength),
                  ),
                ),
                Semantics(
                  identifier: 'cycle-estimate-duration',
                  child: TextField(
                    controller: period,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: s.cyclePeriodLength),
                  ),
                ),
                _action(
                  'cycle-estimate-start',
                  start == null ? s.cycleLastStart : _date(context, start!),
                  () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: start ?? DateTime.now(),
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) setState(() => start = date);
                  },
                ),
                if (error != null) Text(error!),
              ],
            ),
          ),
          actions: [
            _CycleDialogButton(
              identifier: 'cycle-setup-cancel',
              onPressed: () => Navigator.pop(context),
              child: Text(s.dialogCancelLabel),
            ),
            _CycleDialogButton(
              identifier: 'cycle-setup-save',
              onPressed: () {
                try {
                  final next = data.copyWith(
                    guessedCycleDays: int.parse(cycle.text),
                    guessedPeriodDays: int.parse(period.text),
                    guessedStart: start,
                    clearExpected: true,
                  );
                  next.validate();
                  Navigator.pop(context, next);
                } catch (_) {
                  setState(() => error = s.cycleInvalid);
                }
              },
              child: Text(s.buttonSaveLabel),
            ),
          ],
        ),
      ),
    );
    // Dispose after the dialog's exit animation has released the text fields.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    cycle.dispose();
    period.dispose();
    if (result != null && context.mounted) {
      await _save(context, repo, result, generation);
    }
  }
}

Future<void> editPeriod(
  BuildContext context,
  CycleRepository repo, {
  PeriodRecord? record,
}) async {
  final data = repo.data;
  final generation = repo.db.activeProfileGeneration;
  var start = record?.start ?? cycleDate(DateTime.now());
  DateTime? end = record?.end;
  var gap = record?.gapBefore ?? false;
  String? error;
  final s = S.of(context);
  final result = await showDialog<CycleData>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(s.cycleEdit),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final isStart in [true, false])
                Semantics(
                  identifier: isStart
                      ? 'cycle-record-start'
                      : 'cycle-record-end',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(isStart ? s.cycleStart : s.cycleEnd),
                    subtitle: Text(
                      isStart
                          ? _date(context, start)
                          : end == null
                          ? s.cycleOngoing
                          : _date(context, end!),
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: isStart ? start : end ?? start,
                        firstDate: isStart ? DateTime(1900) : start,
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          if (isStart) {
                            start = picked;
                            if (end != null && end!.isBefore(start)) end = null;
                          } else {
                            end = picked;
                          }
                        });
                      }
                    },
                  ),
                ),
              Semantics(
                identifier: 'cycle-record-gap',
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.cycleGap),
                  subtitle: Text(s.cycleGapHint),
                  value: gap,
                  onChanged: (v) => setState(() => gap = v ?? false),
                ),
              ),
              if (error != null) Text(error!),
            ],
          ),
        ),
        actions: [
          _CycleDialogButton(
            identifier: 'cycle-record-cancel',
            onPressed: () => Navigator.pop(context),
            child: Text(s.dialogCancelLabel),
          ),
          _CycleDialogButton(
            identifier: 'cycle-record-save',
            onPressed: () {
              final updated = PeriodRecord(
                id: record?.id ?? IdGenerator.getUniqueID(),
                start: start,
                end: end,
                gapBefore: gap,
              );
              final next = data.copyWith(
                records: [
                  ...data.records.where((r) => r.id != updated.id),
                  updated,
                ],
                clearExpected: true,
              );
              try {
                next.validate(today: DateTime.now());
                Navigator.pop(context, next);
              } catch (_) {
                setState(() => error = s.cycleInvalid);
              }
            },
            child: Text(s.buttonSaveLabel),
          ),
        ],
      ),
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
          child: AppCard(
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
                                  child: Text(s.dialogCancelLabel),
                                ),
                                _CycleDialogButton(
                                  identifier: 'cycle-delete-confirm',
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(s.dialogDeleteLabel),
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
