import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/home/presentation/widgets/log_water_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Tap to repeat the last drink. The separate edit action opens the amount
/// control and undo without inserting a drink first.
class QuickWaterWidget extends StatefulWidget {
  const QuickWaterWidget({
    super.key,
    required this.waterMlToday,
    required this.waterGoalMl,
    this.amountMl = 250,
    this.onAdd,
    this.onEdit,
  });

  final int waterMlToday;
  final int waterGoalMl;
  final int amountMl;
  final Future<void> Function(int)? onAdd;
  final VoidCallback? onEdit;

  @override
  State<QuickWaterWidget> createState() => _QuickWaterWidgetState();
}

class _QuickWaterWidgetState extends State<QuickWaterWidget> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Dimens.spacing4,
      children: [
        Semantics(
          identifier: 'home-water-chip',
          child: ActionChip(
            avatar: const Icon(Icons.water_drop_rounded, size: 18),
            label: Text(
              '${s.waterChipLabel(widget.waterMlToday, widget.waterGoalMl)}  +${widget.amountMl} ml',
            ),
            onPressed: _saving ? null : _add,
          ),
        ),
        Semantics(
          identifier: 'home-water-edit',
          child: IconButton(
            tooltip: s.logWaterDialogTitle,
            onPressed: _saving
                ? null
                : () {
                    if (widget.onEdit != null) {
                      widget.onEdit!();
                    } else {
                      showDialog<void>(
                        context: context,
                        builder: (_) =>
                            LogWaterDialog(initialAmountMl: widget.amountMl),
                      );
                    }
                  },
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
        ),
      ],
    );
  }

  Future<void> _add() async {
    setState(() => _saving = true);
    try {
      final add = widget.onAdd ?? locator<HomeBloc>().addWaterIntake;
      await add(widget.amountMl);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
