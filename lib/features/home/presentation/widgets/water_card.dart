import 'dart:math' as math;

import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/water_format.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/home/presentation/widgets/log_water_dialog.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/water_goal_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

enum _WaterMenuAction { log, undo, goal }

/// Water as a single dashboard card: a title carrying the day's total in
/// litres, an overflow menu for the fiddly cases, and one row of cups that is
/// the whole control surface. Tapping a cup that is not yet full pours the
/// selected drink amount; tapping a full one takes that amount back off the
/// day. Each cup is worth exactly the current drink amount and the cup count
/// is derived from that — never the other way round, because dividing the goal
/// by a rounded cup count made a single tap fill more than one cup.
class WaterCard extends StatefulWidget {
  const WaterCard({
    super.key,
    required this.waterMlToday,
    required this.waterGoalMl,
    this.amountMl = 250,
    this.onAdd,
    this.onRemove,
    this.onEdit,
    this.onUndo,
    this.onEditGoal,
  });

  final int waterMlToday;
  final int waterGoalMl;
  final int amountMl;
  final Future<void> Function(int)? onAdd;
  final Future<void> Function(int)? onRemove;
  final VoidCallback? onEdit;
  final Future<bool> Function()? onUndo;
  final VoidCallback? onEditGoal;

  @override
  State<WaterCard> createState() => _WaterCardState();
}

class _WaterCardState extends State<WaterCard> {
  /// Cups are only as wide as the row can afford. Below [_minCupSlot] the row
  /// scrolls instead of shrinking further, so a 100 ml drink size stays
  /// tappable rather than turning into a strip of slivers.
  static const double _minCupSlot = 40;
  static const double _maxCupSlot = 56;
  static const double _cupRowHeight = 54;
  static const double _cupHeight = 44;

  bool _saving = false;

  int get _drinkMl => widget.amountMl > 0 ? widget.amountMl : 250;

  /// Goal cups, plus the one cup currently being filled. Past the goal that
  /// extra cup is what keeps drinking possible, instead of leaving a row of
  /// full cups and no way to add another.
  int get _cupCount {
    final goalCups = (widget.waterGoalMl / _drinkMl).ceil();
    final pouredCups = (widget.waterMlToday / _drinkMl).floor() + 1;
    return math.max(math.max(goalCups, pouredCups), 1);
  }

  double _fillFor(int index) =>
      ((widget.waterMlToday - index * _drinkMl) / _drinkMl).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final reached =
        widget.waterGoalMl > 0 && widget.waterMlToday >= widget.waterGoalMl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing16,
        Dimens.spacing8,
        Dimens.spacing16,
        Dimens.spacing4,
      ),
      child: AppCard(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          Dimens.spacing20,
          Dimens.spacing12,
          Dimens.spacing8,
          Dimens.spacing16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _buildHeader(s, theme, palette, reached)),
                _buildMenu(s),
              ],
            ),
            const SizedBox(height: Dimens.spacing8),
            Padding(
              padding: const EdgeInsets.only(right: Dimens.spacing12),
              child: Semantics(
                identifier: 'home-water-cups',
                child: _buildCupRow(s, palette),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(S s, ThemeData theme, AppPalette palette, bool reached) {
    final currentText = WaterFormat.litresText(widget.waterMlToday);
    final goalText = WaterFormat.litresText(widget.waterGoalMl);
    // Split the localized template on a sentinel so the flipping digits sit
    // wherever the translation puts them. The brackets are punctuation the
    // card adds around the whole phrase, not part of the translated string.
    const sentinel = '\u0000';
    final parts = s.waterTotalLabel(sentinel, goalText).split(sentinel);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Dimens.spacing8,
      children: [
        Text(
          s.trendsWaterLabel,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Semantics(
          label: s.waterTotalLabel(currentText, goalText),
          excludeSemantics: true,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: AnimatedFlipCounter(
              value: WaterFormat.litres(widget.waterMlToday),
              fractionDigits: 1,
              decimalSeparator: WaterFormat.decimalSeparator(),
              duration: AppMotion.durationMedium,
              curve: AppMotion.emphasized,
              prefix: '(${parts.first}',
              suffix: "${parts.length > 1 ? parts[1] : ''})",
              textStyle: theme.textTheme.bodyMedium?.copyWith(
                color: reached ? palette.water : palette.textMuted,
                fontWeight: reached ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
        if (reached)
          Semantics(
            label: s.waterGoalReachedLabel,
            child: Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: palette.water,
            ),
          ),
      ],
    );
  }

  Widget _buildMenu(S s) {
    return Semantics(
      identifier: 'home-water-menu',
      container: true,
      child: PopupMenuButton<_WaterMenuAction>(
        tooltip: s.logWaterDialogTitle,
        icon: const Icon(Icons.more_vert_rounded, size: 20),
        onSelected: _onMenuSelected,
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _WaterMenuAction.log,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.water_drop_outlined),
              title: Text(s.logWaterDialogTitle),
            ),
          ),
          PopupMenuItem(
            value: _WaterMenuAction.undo,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.undo_rounded),
              title: Text(s.logWaterUndoLabel),
            ),
          ),
          PopupMenuItem(
            value: _WaterMenuAction.goal,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined),
              title: Text(s.settingsWaterGoalLabel),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCupRow(S s, AppPalette palette) {
    final count = _cupCount;
    final frontier = widget.waterMlToday ~/ _drinkMl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final ideal = available / count;
        final scrolls = ideal < _minCupSlot;
        final slot = scrolls
            ? _minCupSlot + 4
            : ideal.clamp(_minCupSlot, _maxCupSlot);

        Widget cup(int index) {
          final fill = _fillFor(index);
          return _WaterCup(
            key: ValueKey('water-cup-$index'),
            fill: fill,
            showAdd: index == frontier,
            water: palette.water,
            slotWidth: slot,
            slotHeight: _cupRowHeight,
            cupHeight: _cupHeight,
            semanticsLabel: fill >= 1
                ? s.logWaterRemoveAmountLabel(_drinkMl)
                : s.logWaterAmountLabel(_drinkMl),
            onTap: _saving ? null : () => _onCupTap(index),
          );
        }

        if (!scrolls) {
          return SizedBox(
            height: _cupRowHeight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (var i = 0; i < count; i++) cup(i)],
            ),
          );
        }
        return SizedBox(
          height: _cupRowHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            primary: false,
            itemExtent: slot,
            itemCount: count,
            itemBuilder: (context, index) => cup(index),
          ),
        );
      },
    );
  }

  void _onCupTap(int index) {
    // A full cup is the only one that takes water away. Everything else —
    // empty, or the part-filled cup at the frontier carrying the "+" — pours.
    if (_fillFor(index) >= 1) {
      _run(() {
        final remove = widget.onRemove ?? locator<HomeBloc>().removeWaterIntake;
        return remove(_drinkMl);
      });
    } else {
      _run(() {
        final add = widget.onAdd ?? locator<HomeBloc>().addWaterIntake;
        return add(_drinkMl);
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onMenuSelected(_WaterMenuAction action) {
    switch (action) {
      case _WaterMenuAction.log:
        if (widget.onEdit != null) {
          widget.onEdit!();
        } else {
          showDialog<void>(
            context: context,
            builder: (_) => LogWaterDialog(initialAmountMl: widget.amountMl),
          );
        }
      case _WaterMenuAction.undo:
        _undo();
      case _WaterMenuAction.goal:
        if (widget.onEditGoal != null) {
          widget.onEditGoal!();
        } else {
          showDialog<void>(
            context: context,
            builder: (_) => WaterGoalDialog(
              settingsBloc: locator<SettingsBloc>(),
              homeBloc: locator<HomeBloc>(),
            ),
          );
        }
    }
  }

  Future<void> _undo() async {
    final messenger = ScaffoldMessenger.of(context);
    final label = S.of(context).logWaterNothingToUndoLabel;
    final undo = widget.onUndo ?? locator<HomeBloc>().undoLastWaterIntake;
    final undone = await undo();
    if (!mounted || undone) return;
    messenger.showSnackBar(SnackBar(content: Text(label)));
  }
}

/// One cup. The fill level tweens on every change, so pouring and removing
/// both read as a level moving rather than a value snapping, and a pour
/// additionally kicks off a short, self-damping splash: the surface ripples
/// and the cup gives one small squash-and-stretch. Both animations are finite
/// — nothing loops here, so the widget settles and tests can pump it out.
class _WaterCup extends StatefulWidget {
  const _WaterCup({
    super.key,
    required this.fill,
    required this.showAdd,
    required this.water,
    required this.slotWidth,
    required this.slotHeight,
    required this.cupHeight,
    required this.semanticsLabel,
    this.onTap,
  });

  final double fill;
  final bool showAdd;
  final Color water;
  final double slotWidth;
  final double slotHeight;
  final double cupHeight;
  final String semanticsLabel;
  final VoidCallback? onTap;

  @override
  State<_WaterCup> createState() => _WaterCupState();
}

class _WaterCupState extends State<_WaterCup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _splash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant _WaterCup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fill > oldWidget.fill) {
      _splash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _splash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final cupWidth = math.max(
      22.0,
      math.min(widget.slotWidth - 6, widget.cupHeight * 0.82),
    );
    return Semantics(
      label: widget.semanticsLabel,
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.semanticsLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  widget.onTap!();
                },
          child: SizedBox(
            width: widget.slotWidth,
            height: widget.slotHeight,
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: widget.fill),
                duration: AppMotion.durationMedium,
                curve: AppMotion.emphasized,
                builder: (context, fill, _) => AnimatedBuilder(
                  animation: _splash,
                  builder: (context, _) {
                    final t = _splash.isAnimating ? _splash.value : 0.0;
                    // One squash-and-stretch beat, then nothing.
                    final pop = t <= 0 || t >= 0.45
                        ? 1.0
                        : 1 + 0.14 * math.sin(t / 0.45 * math.pi);
                    return Transform.scale(
                      scale: pop,
                      child: CustomPaint(
                        painter: _CupPainter(
                          fill: fill,
                          splash: t,
                          water: widget.water,
                          isDark: isDark,
                        ),
                        child: SizedBox(
                          width: cupWidth,
                          height: widget.cupHeight,
                          child: AnimatedOpacity(
                            opacity: widget.showAdd ? 1 : 0,
                            duration: AppMotion.durationShort,
                            // The badge sits on its own disc: the water line
                            // can cross it at any level, and a bare glyph
                            // would lose contrast exactly there.
                            child: Center(child: _addBadge(palette, cupWidth)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tapered tumbler: pale tinted glass, a water body with a wavy surface and
/// a hairline rim. Drawn rather than composed from a Material icon so the
/// water level is a real level — and can slosh — instead of a clipped glyph.
/// The "tap here next" affordance on the frontier cup.
Widget _addBadge(AppPalette palette, double cupWidth) {
  final size = math.min(22.0, cupWidth * 0.62);
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: palette.surface,
      shape: BoxShape.circle,
      border: Border.all(
        color: palette.water.withValues(alpha: 0.35),
        width: Dimens.hairline,
      ),
    ),
    child: Icon(Icons.add_rounded, size: size * 0.72, color: palette.water),
  );
}

class _CupPainter extends CustomPainter {
  const _CupPainter({
    required this.fill,
    required this.splash,
    required this.water,
    required this.isDark,
  });

  final double fill;
  final double splash;
  final Color water;
  final bool isDark;

  static Path glassPath(Size size) {
    final w = size.width;
    final h = size.height;
    final taper = w * 0.13;
    final r = w * 0.16;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w - taper, h - r)
      ..quadraticBezierTo(w - taper, h, w - taper - r, h)
      ..lineTo(taper + r, h)
      ..quadraticBezierTo(taper, h, taper, h - r)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final glass = glassPath(size);
    final rect = Offset.zero & size;

    canvas.drawPath(
      glass,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            water.withValues(alpha: isDark ? 0.12 : 0.08),
            water.withValues(alpha: isDark ? 0.24 : 0.18),
          ],
        ).createShader(rect),
    );

    if (fill > 0) {
      canvas.save();
      canvas.clipPath(glass);
      final top = size.height * (1 - fill);
      // The splash decays to nothing, so an idle cup has a flat surface.
      final amplitude = splash <= 0
          ? 0.0
          : (1 - splash) * (1 - splash) * size.height * 0.07;
      final phase = splash * math.pi * 6;
      final surface = Path()..moveTo(-1, top);
      for (var x = -1.0; x <= size.width + 1; x += 1.5) {
        surface.lineTo(
          x,
          top + amplitude * math.sin((x / size.width) * math.pi * 2.2 + phase),
        );
      }
      surface
        ..lineTo(size.width + 1, size.height + 1)
        ..lineTo(-1, size.height + 1)
        ..close();
      canvas.drawPath(
        surface,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [water.withValues(alpha: 0.72), water],
          ).createShader(rect),
      );
      canvas.restore();
    }

    canvas.drawPath(
      glass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = Dimens.hairline
        ..color = water.withValues(alpha: isDark ? 0.45 : 0.32),
    );
  }

  @override
  bool shouldRepaint(_CupPainter old) =>
      old.fill != fill ||
      old.splash != splash ||
      old.water != water ||
      old.isDark != isDark;
}
