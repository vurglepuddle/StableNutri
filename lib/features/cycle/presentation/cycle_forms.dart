import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/features/cycle/presentation/cycle_card.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/features/cycle/domain/cycle_data.dart';
import 'package:opennutritracker/features/cycle/presentation/cycle_calendar.dart';
import 'package:opennutritracker/generated/l10n.dart';

String cycleDateLabel(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(context).formatMediumDate(date);

/// Full-height editing leaves room for the calendar and large text.
class CycleFormPage extends StatelessWidget {
  final String title;
  final String identifier;
  final List<Widget> children;
  final VoidCallback? onSave;
  final String? error;
  const CycleFormPage({
    super.key,
    required this.title,
    required this.identifier,
    required this.children,
    required this.onSave,
    this.error,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 72,
      title: Text(
        title,
        maxLines: 2,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
    body: ListView(padding: const EdgeInsets.all(16), children: children),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 8,
            children: [
              Semantics(
                identifier: '$identifier-cancel',
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(S.of(context).cycleCancel),
                ),
              ),
              Semantics(
                identifier: '$identifier-save',
                child: FilledButton(
                  onPressed: onSave,
                  child: Text(S.of(context).buttonSaveLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

Future<DateTime?> pickCycleDate(
  BuildContext context, {
  required String title,
  required CycleData data,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  var selected = cycleDate(initialDate);
  return Navigator.of(context).push<DateTime>(
    MaterialPageRoute(
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => CycleFormPage(
          title: title,
          identifier: 'cycle-date',
          onSave: () => Navigator.pop(context, selected),
          children: [
            Text(
              cycleDateLabel(context, selected),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            CycleCard(
              padding: const EdgeInsets.all(8),
              child: CycleCalendar(
                data: data,
                initialDay: selected,
                firstDay: firstDate,
                lastDay: lastDate,
                start: selected,
                onSelected: (date, _) => setState(() => selected = date),
              ),
            ),
            const SizedBox(height: 12),
            const CycleCalendarLegend(),
          ],
        ),
      ),
    ),
  );
}

class CycleSetupPage extends StatefulWidget {
  final CycleData data;
  const CycleSetupPage({super.key, required this.data});
  @override
  State<CycleSetupPage> createState() => _CycleSetupPageState();
}

class _CycleSetupPageState extends State<CycleSetupPage> {
  late final cycle = TextEditingController(
    text: '${widget.data.guessedCycleDays}',
  );
  late final period = TextEditingController(
    text: '${widget.data.guessedPeriodDays}',
  );
  late DateTime? start = widget.data.guessedStart;
  String? error;

  @override
  void dispose() {
    cycle.dispose();
    period.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return CycleFormPage(
      title: s.cycleSetup,
      identifier: 'cycle-setup',
      error: error,
      onSave: () {
        try {
          final next = widget.data.copyWith(
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
      children: [
        Text(s.cycleSetupHint, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        CycleCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _lengthField(
                context,
                'cycle-estimate-length',
                s.cycleLength,
                s.cycleLengthHint,
                cycle,
              ),
              const SizedBox(height: 24),
              _lengthField(
                context,
                'cycle-estimate-duration',
                s.cyclePeriodLength,
                s.cyclePeriodHint,
                period,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CycleCard(
          child: Semantics(
            identifier: 'cycle-estimate-start',
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              title: Text(s.cycleLastStart),
              subtitle: Text(
                start == null
                    ? s.cycleChooseDate
                    : cycleDateLabel(context, start!),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final date = await pickCycleDate(
                  context,
                  title: s.cycleLastStart,
                  data: widget.data,
                  initialDate: start ?? DateTime.now(),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (date != null && mounted) setState(() => start = date);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _lengthField(
    BuildContext context,
    String id,
    String label,
    String hint,
    TextEditingController controller,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(hint, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      Semantics(
        identifier: id,
        label: label,
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          decoration: const InputDecoration(),
        ),
      ),
    ],
  );
}

class PeriodEditorPage extends StatefulWidget {
  final CycleData data;
  final PeriodRecord? record;
  final bool past;
  const PeriodEditorPage({
    super.key,
    required this.data,
    this.record,
    this.past = false,
  });
  @override
  State<PeriodEditorPage> createState() => _PeriodEditorPageState();
}

class _PeriodEditorPageState extends State<PeriodEditorPage> {
  late DateTime? start =
      widget.record?.start ?? (widget.past ? null : cycleDate(DateTime.now()));
  late DateTime? end = widget.record?.end;
  late bool ongoing = widget.record != null
      ? widget.record!.end == null
      : !widget.past;
  late bool gap = widget.record?.gapBefore ?? false;
  String? error;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return CycleFormPage(
      title: widget.past ? s.cycleAddPast : s.cycleEdit,
      identifier: 'cycle-record',
      error: error,
      onSave: start == null || (!ongoing && end == null)
          ? null
          : () {
              final updated = PeriodRecord(
                id: widget.record?.id ?? IdGenerator.getUniqueID(),
                start: start!,
                end: ongoing ? null : end,
                gapBefore: gap,
              );
              final next = widget.data.copyWith(
                records: [
                  ...widget.data.records.where((r) => r.id != updated.id),
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
      children: [
        Text(
          ongoing ? s.cyclePickStart : s.cyclePickRange,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        Text(
          start == null
              ? s.cycleChooseDate
              : ongoing
              ? '${cycleDateLabel(context, start!)} \u00b7 ${s.cycleOngoing}'
              : end == null
              ? cycleDateLabel(context, start!)
              : '${cycleDateLabel(context, start!)} \u2013 ${cycleDateLabel(context, end!)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        CycleCard(
          padding: const EdgeInsets.all(8),
          child: CycleCalendar(
            // Keep all saved dates visible, including the record being edited.
            data: widget.data,
            initialDay: start ?? DateTime.now(),
            firstDay: DateTime(1900),
            lastDay: DateTime.now(),
            start: start,
            end: end,
            range: !ongoing,
            showPrediction: false,
            onSelected: (first, last) => setState(() {
              start = first;
              end = last;
              error = null;
            }),
          ),
        ),
        const SizedBox(height: 12),
        const CycleCalendarLegend(showPrediction: false),
        const SizedBox(height: 20),
        CycleCard(
          child: Column(
            children: [
              Semantics(
                identifier: 'cycle-record-ongoing',
                child: SwitchListTile.adaptive(
                  title: Text(s.cycleOngoing),
                  value: ongoing,
                  onChanged: (value) => setState(() {
                    ongoing = value;
                    end = null;
                    error = null;
                  }),
                ),
              ),
              const Divider(height: 1),
              Semantics(
                identifier: 'cycle-record-gap',
                child: CheckboxListTile(
                  title: Text(s.cycleGap),
                  subtitle: Text(s.cycleGapHint),
                  value: gap,
                  onChanged: (value) => setState(() => gap = value ?? false),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
