import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/generated/l10n.dart';

class DailyIntakeRangeDialog extends StatefulWidget {
  final double initialLowerKcal;
  final double initialUpperKcal;
  final bool usesKilojoules;
  final Future<void> Function(double lowerKcal, double upperKcal) onSave;

  const DailyIntakeRangeDialog({
    super.key,
    required this.initialLowerKcal,
    required this.initialUpperKcal,
    required this.usesKilojoules,
    required this.onSave,
  });

  @override
  State<DailyIntakeRangeDialog> createState() => _DailyIntakeRangeDialogState();
}

class _DailyIntakeRangeDialogState extends State<DailyIntakeRangeDialog> {
  late final TextEditingController _lowerController;
  late final TextEditingController _upperController;
  bool _hasBoundsError = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lowerController = TextEditingController(
      text: _toDisplay(widget.initialLowerKcal).round().toString(),
    );
    _upperController = TextEditingController(
      text: _toDisplay(widget.initialUpperKcal).round().toString(),
    );
  }

  @override
  void dispose() {
    _lowerController.dispose();
    _upperController.dispose();
    super.dispose();
  }

  double _toDisplay(double kcal) =>
      widget.usesKilojoules ? UnitCalc.kcalToKj(kcal) : kcal;

  double _toKcal(double display) =>
      widget.usesKilojoules ? UnitCalc.kjToKcal(display) : display;

  Future<void> _save() async {
    final lowerDisplay = double.tryParse(_lowerController.text);
    final upperDisplay = double.tryParse(_upperController.text);
    final lower = lowerDisplay == null ? null : _toKcal(lowerDisplay);
    final upper = upperDisplay == null ? null : _toKcal(upperDisplay);
    final isValid =
        lower != null &&
        upper != null &&
        lower > 0 &&
        upper <= 20000 &&
        lower < upper;
    if (!isValid) {
      setState(() => _hasBoundsError = true);
      return;
    }

    setState(() {
      _hasBoundsError = false;
      _saving = true;
    });
    await widget.onSave(lower, upper);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final unit = widget.usesKilojoules ? s.kjLabel : s.kcalLabel;
    return AlertDialog(
      title: Text(s.dailyIntakeRangeLabel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            identifier: 'daily-intake-range-lower-input',
            child: TextField(
              controller: _lowerController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '${s.rangeLowerLabel} ($unit)',
              ),
              onChanged: (_) => setState(() => _hasBoundsError = false),
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            identifier: 'daily-intake-range-upper-input',
            child: TextField(
              controller: _upperController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: '${s.rangeUpperLabel} ($unit)',
              ),
              onChanged: (_) => setState(() => _hasBoundsError = false),
            ),
          ),
          if (_hasBoundsError) ...[
            const SizedBox(height: 8),
            Text(
              s.rangeBoundsErrorLabel,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        Semantics(
          identifier: 'daily-intake-range-cancel',
          child: TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(s.dialogCancelLabel),
          ),
        ),
        Semantics(
          identifier: 'daily-intake-range-save',
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(s.buttonSaveLabel),
          ),
        ),
      ],
    );
  }
}
