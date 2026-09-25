import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/serving_label_localizer.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_quantity_units.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// How much of a food, in which unit, and for which meal: the first thing
/// on the food screen, whether the food is being added or was logged.
class MealAmountPicker extends StatefulWidget {
  final MealEntity product;
  final TextEditingController quantityTextController;
  final String selectedUnit;
  final bool enabled;
  final IntakeTypeEntity intakeType;
  final Function(String?, String?) onQuantityOrUnitChanged;
  final ValueChanged<IntakeTypeEntity> onIntakeTypeChanged;

  const MealAmountPicker({
    super.key,
    required this.product,
    required this.quantityTextController,
    required this.selectedUnit,
    required this.enabled,
    required this.intakeType,
    required this.onQuantityOrUnitChanged,
    required this.onIntakeTypeChanged,
  });

  @override
  State<MealAmountPicker> createState() => _MealAmountPickerState();
}

class _MealAmountPickerState extends State<MealAmountPicker> {
  final _quantityFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.quantityTextController.addListener(_onQuantityChanged);
    _quantityFocusNode.addListener(_onQuantityFocusChanged);
  }

  @override
  void didUpdateWidget(MealAmountPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quantityTextController != widget.quantityTextController) {
      oldWidget.quantityTextController.removeListener(_onQuantityChanged);
      widget.quantityTextController.addListener(_onQuantityChanged);
    }
  }

  @override
  void dispose() {
    _quantityFocusNode.removeListener(_onQuantityFocusChanged);
    _quantityFocusNode.dispose();
    widget.quantityTextController.removeListener(_onQuantityChanged);
    super.dispose();
  }

  void _onQuantityFocusChanged() {
    if (_quantityFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_quantityFocusNode.hasFocus) return;
        _selectAllQuantityText();
      });
    }
  }

  void _selectAllQuantityText() {
    final text = widget.quantityTextController.text;
    widget.quantityTextController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.length,
    );
  }

  void _onQuantityChanged() {
    widget.onQuantityOrUnitChanged(
      widget.quantityTextController.text,
      widget.selectedUnit,
    );
  }

  /// One tap to a common amount instead of typing: servings count in
  /// halves, weights and volumes in usual portions.
  List<num> get _presets => widget.selectedUnit == 'serving'
      ? const [0.5, 1, 1.5, 2, 3]
      : const [50, 100, 150, 200, 250];

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Semantics(
                identifier: 'meal-detail-quantity',
                child: TextFormField(
                  enabled: widget.enabled,
                  controller: widget.quantityTextController,
                  focusNode: _quantityFocusNode,
                  onTap: _selectAllQuantityText,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+([.,]\d{0,2})?$'),
                    ),
                  ],
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(
                      borderRadius: Dimens.borderRadiusM,
                    ),
                    labelText: s.quantityLabel,
                  ),
                ),
              ),
            ),
            const SizedBox(width: Dimens.spacing12),
            Expanded(
              flex: 3,
              child: Semantics(
                identifier: 'meal-detail-unit',
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  itemHeight: null,
                  initialValue: widget.selectedUnit,
                  key: ValueKey(widget.selectedUnit),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(
                      borderRadius: Dimens.borderRadiusM,
                    ),
                    labelText: s.unitLabel,
                  ),
                  items: [
                    for (final unit in MealQuantityUnits(widget.product).values)
                      _unitItem(context, unit),
                  ],
                  onChanged: widget.enabled
                      ? (value) => widget.onQuantityOrUnitChanged(
                          widget.quantityTextController.text,
                          value,
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
        if (widget.enabled) ...[
          const SizedBox(height: Dimens.spacing8),
          Wrap(
            spacing: Dimens.spacing8,
            children: [
              for (final preset in _presets)
                ActionChip(
                  label: Text(_presetLabel(preset)),
                  onPressed: () {
                    widget.quantityTextController.text = _presetLabel(preset);
                    widget.onQuantityOrUnitChanged(
                      _presetLabel(preset),
                      widget.selectedUnit,
                    );
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: Dimens.spacing12),
        Semantics(
          identifier: 'meal-detail-meal-type',
          child: DropdownButtonFormField<IntakeTypeEntity>(
            isExpanded: true,
            initialValue: widget.intakeType,
            key: ValueKey(widget.intakeType),
            decoration: InputDecoration(
              border: const OutlineInputBorder(
                borderRadius: Dimens.borderRadiusM,
              ),
              labelText: s.mealTypeLabel,
            ),
            items: [
              for (final type in IntakeTypeEntity.values)
                DropdownMenuItem(
                  value: type,
                  child: Row(
                    children: [
                      Icon(type.getIconData(), size: 20),
                      const SizedBox(width: Dimens.spacing12),
                      Flexible(
                        child: Text(
                          _mealName(s, type),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (type) {
              if (type != null) widget.onIntakeTypeChanged(type);
            },
          ),
        ),
      ],
    );
  }

  static String _presetLabel(num preset) =>
      preset == preset.roundToDouble() ? '${preset.round()}' : '$preset';

  static String _mealName(S s, IntakeTypeEntity type) => switch (type) {
    IntakeTypeEntity.breakfast => s.breakfastLabel,
    IntakeTypeEntity.lunch => s.lunchLabel,
    IntakeTypeEntity.dinner => s.dinnerLabel,
    IntakeTypeEntity.snack => s.snackLabel,
  };

  DropdownMenuItem<String> _getServingDropdownItem(BuildContext context) {
    // Custom meals are seeded from MealEntity.empty(), which carries an empty
    // servingSize string rather than null. An empty (or whitespace-only)
    // description should fall through to the constructed label so the option
    // doesn't render blank — otherwise '' wins over the ?? fallback (#495).
    final servingSize = widget.product.servingSize;
    // Serving labels are stored in English (see MealEntity._spServingLabel);
    // translate the common household units at display time.
    final quantity = widget.product.scalableServingQuantity;
    final amount = quantity == null
        ? ''
        : ' (${_presetLabel(double.parse(quantity.toStringAsFixed(1)))}'
              ' ${widget.product.servingUnit ?? ''})';
    // A recipe's description counts its servings ("2 servings"), which read
    // as the size of one; show one serving's weight instead.
    final describesOne =
        widget.product.source != MealSourceEntity.recipe &&
        servingSize != null &&
        servingSize.trim().isNotEmpty;
    final servingText = describesOne
        ? localizeServingLabel(S.of(context), servingSize)
        : '${S.of(context).servingLabel}$amount';
    return DropdownMenuItem(
      value: UnitDropdownItem.serving.toString(),
      child: Text(servingText, overflow: TextOverflow.ellipsis, maxLines: 1),
    );
  }

  DropdownMenuItem<String> _unitItem(BuildContext context, String unit) {
    if (unit == 'serving') return _getServingDropdownItem(context);
    final s = S.of(context);
    final label = switch (unit) {
      'g' => s.gramUnit,
      'oz' => s.ozUnit,
      'ml' => s.milliliterUnit,
      'fl.oz' => s.flOzUnit,
      _ => '${s.notAvailableLabel} (${s.gramMilliliterUnit})',
    };
    return DropdownMenuItem(
      value: unit,
      child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
    );
  }
}
