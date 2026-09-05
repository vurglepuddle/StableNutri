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
    final drinkMl = widget.amountMl > 0 ? widget.amountMl : 250;
    final goalGlasses = (widget.waterGoalMl / drinkMl).ceil();
    final glassCount = goalGlasses > 0 ? goalGlasses : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
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
                            builder: (_) => LogWaterDialog(
                              initialAmountMl: widget.amountMl,
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
            ),
          ],
        ),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false,
            itemExtent: 48,
            itemCount: glassCount,
            itemBuilder: (context, index) => IconButton(
              key: ValueKey('water-glass-$index'),
              tooltip: s.logWaterAmountLabel(widget.amountMl),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: _saving ? null : _add,
              icon: _WaterGlass(
                fill: ((widget.waterMlToday - index * drinkMl) / drinkMl).clamp(
                  0.0,
                  1.0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _add() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final add = widget.onAdd ?? locator<HomeBloc>().addWaterIntake;
      await add(widget.amountMl);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _WaterGlass extends StatelessWidget {
  final double fill;
  const _WaterGlass({required this.fill});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        width: 28,
        height: 28,
        child: Stack(
          children: [
            Icon(
              Icons.local_drink_outlined,
              size: 28,
              color: colors.onSurfaceVariant,
            ),
            ClipRect(
              clipper: _GlassFillClipper(fill),
              child: Icon(Icons.local_drink, size: 28, color: colors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassFillClipper extends CustomClipper<Rect> {
  final double fill;
  const _GlassFillClipper(this.fill);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, size.height * (1 - fill), size.width, size.height);

  @override
  bool shouldReclip(_GlassFillClipper oldClipper) => oldClipper.fill != fill;
}
