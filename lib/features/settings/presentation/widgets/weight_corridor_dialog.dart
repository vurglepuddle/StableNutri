import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/body_weight_input.dart';
import 'package:opennutritracker/generated/l10n.dart';

class WeightCorridorDialog extends StatefulWidget {
  final double initialLowerKg;
  final double initialUpperKg;
  final BodyWeightUnit unit;
  final Future<void> Function(double lowerKg, double upperKg) onSave;

  const WeightCorridorDialog({
    super.key,
    required this.initialLowerKg,
    required this.initialUpperKg,
    required this.unit,
    required this.onSave,
  });

  @override
  State<WeightCorridorDialog> createState() => _WeightCorridorDialogState();
}

class _WeightCorridorDialogState extends State<WeightCorridorDialog> {
  late double? _lowerKg = widget.initialLowerKg;
  late double? _upperKg = widget.initialUpperKg;
  bool _hasBoundsError = false;
  bool _saving = false;

  Future<void> _save() async {
    final lower = _lowerKg;
    final upper = _upperKg;
    if (lower == null || upper == null || lower >= upper) {
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
    return AlertDialog(
      title: Text(s.weightCorridorLabel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.rangeLowerLabel),
          const SizedBox(height: 4),
          BodyWeightInput(
            initialKg: widget.initialLowerKg,
            unit: widget.unit,
            identifierPrefix: 'weight-corridor-lower',
            autofocus: true,
            onChangedKg: (value) => setState(() {
              _lowerKg = value;
              _hasBoundsError = false;
            }),
          ),
          const SizedBox(height: 12),
          Text(s.rangeUpperLabel),
          const SizedBox(height: 4),
          BodyWeightInput(
            initialKg: widget.initialUpperKg,
            unit: widget.unit,
            identifierPrefix: 'weight-corridor-upper',
            onChangedKg: (value) => setState(() {
              _upperKg = value;
              _hasBoundsError = false;
            }),
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
          identifier: 'weight-corridor-cancel',
          child: TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(s.dialogCancelLabel),
          ),
        ),
        Semantics(
          identifier: 'weight-corridor-save',
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(s.buttonSaveLabel),
          ),
        ),
      ],
    );
  }
}
