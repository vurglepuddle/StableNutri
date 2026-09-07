import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Rounds three macro percentage shares to integers that sum to exactly 100.
///
/// Uses the largest-remainder method so the result stays as close as possible
/// to the unconstrained ratio. Independent rounding is unsafe here: two
/// half-up .5 remainders produce 101, and `SettingsBloc.setMacroGoals` stores
/// via `toInt()/100`, which truncates.
@visibleForTesting
(int carbs, int protein, int fat) roundMacroPercentsToHundred(
  double carbsPct,
  double proteinPct,
  double fatPct,
) {
  const defaultCarbs = 60.0;
  const defaultProtein = 15.0;
  const defaultFat = 25.0;

  final values = [carbsPct, proteinPct, fatPct];
  final total = values.fold<double>(0, (sum, v) => sum + v);
  final scaled = total <= 0
      ? const [defaultCarbs, defaultProtein, defaultFat]
      : [for (final v in values) v * 100.0 / total];

  final floors = [for (final v in scaled) v.floor()];
  final remaining = 100 - floors.reduce((a, b) => a + b);
  final order = List<int>.generate(3, (i) => i)
    ..sort((a, b) {
      final fracCmp = (scaled[b] - floors[b]).compareTo(scaled[a] - floors[a]);
      if (fracCmp != 0) return fracCmp;
      // Prefer the originally larger share; fall back to lower index for a
      // deterministic triple when both remainder and magnitude match.
      final sizeCmp = scaled[b].compareTo(scaled[a]);
      if (sizeCmp != 0) return sizeCmp;
      return a.compareTo(b);
    });
  final result = List<int>.from(floors);
  for (var i = 0; i < remaining; i++) {
    result[order[i]]++;
  }
  return (result[0], result[1], result[2]);
}

/// Three sliders that distribute the daily kcal goal across
/// carbohydrate, protein, and fat. Moving any one slider rebalances
/// the other two against 100% so the trio always adds up, with each
/// macro pinned to a 5% floor so the diary still has something to
/// track against if a user pulls one slider all the way down.
class MacroSplitDialog extends StatefulWidget {
  final SettingsBloc settingsBloc;
  final HomeBloc homeBloc;

  const MacroSplitDialog({
    super.key,
    required this.settingsBloc,
    required this.homeBloc,
  });

  @override
  State<MacroSplitDialog> createState() => _MacroSplitDialogState();
}

class _MacroSplitDialogState extends State<MacroSplitDialog> {
  static const double _defaultCarbsPct = 60;
  static const double _defaultProteinPct = 15;
  static const double _defaultFatPct = 25;

  double _carbsPct = _defaultCarbsPct;
  double _proteinPct = _defaultProteinPct;
  double _fatPct = _defaultFatPct;
  bool _loaded = false;

  late final TextEditingController _carbsController;
  late final TextEditingController _proteinController;
  late final TextEditingController _fatController;

  @override
  void initState() {
    super.initState();
    _carbsController = TextEditingController();
    _proteinController = TextEditingController();
    _fatController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _carbsController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final carbs = await widget.settingsBloc.getUserCarbGoalPct();
    final protein = await widget.settingsBloc.getUserProteinGoalPct();
    final fat = await widget.settingsBloc.getUserFatGoalPct();
    if (!mounted) return;
    setState(() {
      _carbsPct = (carbs ?? _defaultCarbsPct / 100) * 100;
      _proteinPct = (protein ?? _defaultProteinPct / 100) * 100;
      _fatPct = (fat ?? _defaultFatPct / 100) * 100;
      _loaded = true;
    });
    _syncControllers();
  }

  void _syncControllers() {
    _carbsController.text = _carbsPct.round().toString();
    _proteinController.text = _proteinPct.round().toString();
    _fatController.text = _fatPct.round().toString();
  }

  /// Rebalance the two unmoved macros proportionally to their current
  /// ratio so the trio re-sums to 100. Each gets clamped to a 5% floor;
  /// anything that would push another macro below the floor is shaved
  /// off the larger of the two so the floors are always honoured.
  void _redistribute({
    required double moved,
    required void Function(double) setMoved,
    required double otherA,
    required void Function(double) setOtherA,
    required double otherB,
    required void Function(double) setOtherB,
    required double oldMoved,
  }) {
    final delta = moved - oldMoved;
    setMoved(moved);
    final totalOthers = otherA + otherB;
    if (totalOthers <= 0) return;
    final ratioA = otherA / totalOthers;
    final ratioB = otherB / totalOthers;
    var newA = otherA - delta * ratioA;
    var newB = otherB - delta * ratioB;
    if (newA < 5) {
      newB -= 5 - newA;
      newA = 5;
    }
    if (newB < 5) {
      newA -= 5 - newB;
      newB = 5;
    }
    setOtherA(newA);
    setOtherB(newB);
  }

  void _applyTextInput(
    TextEditingController controller,
    double currentValue,
    void Function(double) setter,
  ) {
    final parsed = int.tryParse(controller.text);
    if (parsed == null || parsed < 5 || parsed > 90) {
      _syncControllers();
      return;
    }
    setState(() => setter(parsed.toDouble()));
  }

  Future<void> _save() async {
    // [_redistribute] leaves fractional percentages (e.g. 14.625), and
    // setMacroGoals stores via toInt()/100 — passing the raw doubles
    // truncates each share, so a split the dialog shows as 100% could
    // persist as 99%. Balance to an exact 100% integer triple first.
    final rounded = roundMacroPercentsToHundred(
      _carbsPct,
      _proteinPct,
      _fatPct,
    );
    await widget.settingsBloc.setMacroGoals(
      rounded.$1.toDouble(),
      rounded.$2.toDouble(),
      rounded.$3.toDouble(),
    );
    widget.settingsBloc.add(LoadSettingsEvent());
    widget.homeBloc.add(const LoadItemsEvent());
    await widget.settingsBloc.updateTrackedDay(DateTime.now());
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final totalPct = _carbsPct.round() + _proteinPct.round() + _fatPct.round();
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              s.settingsMacroSplitLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _loaded
                ? () {
                    setState(() {
                      _carbsPct = _defaultCarbsPct;
                      _proteinPct = _defaultProteinPct;
                      _fatPct = _defaultFatPct;
                    });
                    _syncControllers();
                  }
                : null,
            child: Text(s.buttonResetLabel),
          ),
        ],
      ),
      content: !_loaded
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$totalPct% total',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  _MacroRow(
                    label: s.carbsLabel,
                    value: _carbsPct,
                    color: Colors.orange,
                    controller: _carbsController,
                    semanticIdentifier: 'macro-split-carbs',
                    onSliderChanged: (v) => setState(
                      () => _redistribute(
                        moved: v,
                        oldMoved: _carbsPct,
                        setMoved: (x) => _carbsPct = x,
                        otherA: _proteinPct,
                        setOtherA: (x) => _proteinPct = x,
                        otherB: _fatPct,
                        setOtherB: (x) => _fatPct = x,
                      ),
                    ),
                    onSliderEnd: _syncControllers,
                    onTextSubmitted: () => _applyTextInput(
                      _carbsController,
                      _carbsPct,
                      (v) => _carbsPct = v,
                    ),
                  ),
                  _MacroRow(
                    label: s.proteinLabel,
                    value: _proteinPct,
                    color: Colors.blue,
                    controller: _proteinController,
                    semanticIdentifier: 'macro-split-protein',
                    onSliderChanged: (v) => setState(
                      () => _redistribute(
                        moved: v,
                        oldMoved: _proteinPct,
                        setMoved: (x) => _proteinPct = x,
                        otherA: _carbsPct,
                        setOtherA: (x) => _carbsPct = x,
                        otherB: _fatPct,
                        setOtherB: (x) => _fatPct = x,
                      ),
                    ),
                    onSliderEnd: _syncControllers,
                    onTextSubmitted: () => _applyTextInput(
                      _proteinController,
                      _proteinPct,
                      (v) => _proteinPct = v,
                    ),
                  ),
                  _MacroRow(
                    label: s.fatLabel,
                    value: _fatPct,
                    color: Colors.green,
                    controller: _fatController,
                    semanticIdentifier: 'macro-split-fat',
                    onSliderChanged: (v) => setState(
                      () => _redistribute(
                        moved: v,
                        oldMoved: _fatPct,
                        setMoved: (x) => _fatPct = x,
                        otherA: _carbsPct,
                        setOtherA: (x) => _carbsPct = x,
                        otherB: _proteinPct,
                        setOtherB: (x) => _proteinPct = x,
                      ),
                    ),
                    onSliderEnd: _syncControllers,
                    onTextSubmitted: () => _applyTextInput(
                      _fatController,
                      _fatPct,
                      (v) => _fatPct = v,
                    ),
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.dialogCancelLabel),
        ),
        Semantics(
          identifier: 'macro-split-save',
          child: TextButton(
            onPressed: _loaded ? _save : null,
            child: Text(s.dialogOKLabel),
          ),
        ),
      ],
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final TextEditingController controller;
  final String semanticIdentifier;
  final ValueChanged<double> onSliderChanged;
  final VoidCallback onSliderEnd;
  final VoidCallback onTextSubmitted;

  const _MacroRow({
    required this.label,
    required this.value,
    required this.color,
    required this.controller,
    required this.semanticIdentifier,
    required this.onSliderChanged,
    required this.onSliderEnd,
    required this.onTextSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            SizedBox(
              // Scale the field width with the user's text setting so the
              // value and its % suffix stay readable at large font scales.
              width: MediaQuery.textScalerOf(context).scale(96),
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  suffixText: '%',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => onTextSubmitted(),
                onEditingComplete: onTextSubmitted,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: color.withValues(alpha: 0.2),
          ),
          child: Semantics(
            identifier: semanticIdentifier,
            child: Slider(
              min: 5,
              max: 90,
              value: value.clamp(5, 90),
              divisions: 85,
              onChanged: (v) {
                final rounded = v.round().toDouble();
                if (100 - rounded >= 10) {
                  onSliderChanged(rounded);
                }
              },
              onChangeEnd: (_) => onSliderEnd(),
            ),
          ),
        ),
      ],
    );
  }
}
