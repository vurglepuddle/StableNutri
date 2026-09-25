import 'dart:math' as math;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/presentation/widgets/user_image_picker_tile.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/barcode_validator.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/custom_text_input_formatter.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/core/utils/food_name_validator.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/navigation_predicates.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/edit_meal/presentation/bloc/edit_meal_bloc.dart';
import 'package:opennutritracker/features/edit_meal/presentation/widgets/default_meal_image.dart';
import 'package:opennutritracker/features/meal_detail/meal_detail_screen.dart';
import 'package:opennutritracker/features/scanner/util/zxing_logging.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

/// What the nutrition fields are typed against.
enum _Basis { per100, perServing }

/// A number field that remembers the exact value it was filled with. Fields
/// show at most two decimals, and kJ or ounces do not convert back exactly;
/// an untouched field hands back its exact value, so saving a renamed food
/// never nudges its nutrition.
class _NumberField {
  final controller = TextEditingController();
  double? _exact;
  String _shown = '';

  bool get isUnchanged => controller.text == _shown;

  double? get value => isUnchanged
      ? _exact
      : double.tryParse(controller.text.trim().replaceAll(',', '.'));

  void show(double? value) {
    _exact = value;
    _shown = value == null ? '' : _format(value);
    controller.text = _shown;
  }

  /// Rescales whatever the field holds, typed or not.
  void scale(double factor) {
    final current = value;
    show(current == null ? null : current * factor);
  }

  static String _format(double value) {
    final fixed = value.toStringAsFixed(2);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void dispose() => controller.dispose();
}

/// Creates a food, or edits a saved or logged one. Name, brand and barcode
/// come first; then the serving, in grams or millilitres; then nutrition,
/// per 100 g as printed on labels, or per serving when that is what is known.
class EditMealScreen extends StatefulWidget {
  const EditMealScreen({super.key});

  @override
  State<EditMealScreen> createState() => _EditMealScreenState();
}

class _EditMealScreenState extends State<EditMealScreen> {
  final log = Logger('EditMealScreen');
  late MealEntity _mealEntity;
  late DateTime _day;
  late IntakeTypeEntity _intakeTypeEntity;
  late bool _usesImperialUnits;

  late bool _editOnly;
  late bool _snapshotOnly;
  late bool _newFood;

  /// Where the values came from when the form opened pre-filled; null for
  /// a blank form or an edit. While set, empty main values are highlighted.
  String? _prefilledFrom;

  late EditMealBloc _editMealBloc;

  final _nameTextController = TextEditingController();
  final _brandsTextController = TextEditingController();
  final _barcodeTextController = TextEditingController();
  final _serving = _NumberField();
  final _kcal = _NumberField();
  final _carbs = _NumberField();
  final _fat = _NumberField();
  final _protein = _NumberField();
  final _fiber = _NumberField();
  final _saturatedFat = _NumberField();
  final _sugars = _NumberField();
  final _sodium = _NumberField();
  final _calcium = _NumberField();
  final _iron = _NumberField();
  final _potassium = _NumberField();
  final _magnesium = _NumberField();
  final _vitaminD = _NumberField();
  final _vitaminB12 = _NumberField();

  List<_NumberField> get _microFields => [
    _fiber,
    _saturatedFat,
    _sugars,
    _sodium,
    _calcium,
    _iron,
    _potassium,
    _magnesium,
    _vitaminD,
    _vitaminB12,
  ];

  List<_NumberField> get _nutritionFields => [
    _kcal,
    _carbs,
    _fat,
    _protein,
    ..._microFields,
  ];

  /// `g` or `ml`: what the food is measured in, and its serving with it.
  String _unit = 'g';

  /// A food logged by the serving with no weight behind it, such as a
  /// Lifesum import: its values stay per serving and its units are kept.
  bool _countBased = false;

  /// How many of the food's own units make one serving, for [_countBased].
  double _countServing = 1;

  _Basis _basis = _Basis.per100;
  bool _showMoreNutrients = false;

  // Default on so behaviour matches what existing users are used to — the
  // meal is saved to their custom list unless they actively untick the box.
  // #249 adds the *option* to skip the save; it does not change the default.
  bool _saveForLater = true;

  // didChangeDependencies is called on every dependency change, including
  // ones triggered by Navigator pops returning from sub-pages (the barcode
  // scanner among them). Without this guard the controllers would get
  // re-seeded from _mealEntity.code on every return, wiping a value the
  // user just scanned into the field.
  bool _initialised = false;

  /// Tracks the unit the energy field was last rendered in, so that when
  /// the user flips between kcal and kJ in Settings mid-edit we can
  /// re-display the same underlying energy in the new unit. `null` until
  /// the first build seeds the field.
  bool? _lastRenderedUsesKj;

  // #64 follow-up: user-attached photo for a custom meal. Mirrors
  // _mealEntity.localImagePath but is held separately so the picker
  // can update the on-screen preview before the parent entity is
  // rebuilt at save time.
  String? _localImagePath;
  bool _localImageCleared = false;

  @override
  void initState() {
    super.initState();
    // Initialize once, not during build.
    _editMealBloc = locator<EditMealBloc>();
    _editMealBloc.add(InitializeEditMealEvent());
    // Values per serving need a serving size.
    _serving.controller.addListener(_onServingChanged);
    // A highlighted empty value loses its highlight as it is typed.
    for (final field in _mainFields) {
      field.controller.addListener(_onMainValueChanged);
    }
  }

  List<_NumberField> get _mainFields => [_kcal, _carbs, _fat, _protein];

  void _onMainValueChanged() {
    if (_prefilledFrom != null && mounted) setState(() {});
  }

  void _onServingChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;

    final args =
        ModalRoute.of(context)?.settings.arguments as EditMealScreenArguments;
    _mealEntity = args.mealEntity;
    _day = args.day;
    _intakeTypeEntity = args.intakeTypeEntity;
    _usesImperialUnits = args.usesImperialUnits;
    _editOnly = args.editOnly;
    _snapshotOnly = args.snapshotOnly;
    _newFood = args.newFood;
    _prefilledFrom = args.prefilledFrom;

    final meal = _mealEntity;
    _nameTextController.text = meal.name ?? "";
    _brandsTextController.text = meal.brands ?? "";
    // MealEntity.code is dual-purpose: it carries a real product barcode for
    // OFF / FDC scans, but for custom meals MealEntity.empty() seeds it with
    // an internal UUID that the user should never see in the Barcode input.
    // Only show codes that actually look like a retail barcode (8–14 digits);
    // anything else means there isn't a user-visible barcode yet.
    final existingCode = meal.code;
    _barcodeTextController.text =
        (existingCode != null && isBarcodeFormatValid(existingCode))
        ? existingCode
        : "";

    _countBased = !isMeasuredByWeightOrVolume(meal.mealUnit);
    _unit = meal.isLiquid ? 'ml' : 'g';
    final serving = meal.scalableServingQuantity;
    if (_countBased) {
      _countServing = serving ?? 1;
      _basis = _Basis.perServing;
    } else {
      _serving.show(serving == null ? null : _toDisplayQuantity(serving));
    }

    // Energy shows in the user's unit (#177 follow-up); storage stays kcal.
    final usesKj = Provider.of<EnergyUnitProvider>(
      context,
      listen: false,
    ).usesKilojoules;
    final n = meal.nutriments;
    final kcal = n.energyKcal100;
    _kcal.show(kcal == null || !usesKj ? kcal : UnitCalc.kcalToKj(kcal));
    _lastRenderedUsesKj = usesKj;
    _carbs.show(n.carbohydrates100);
    _fat.show(n.fat100);
    _protein.show(n.proteins100);
    _fiber.show(n.fiber100);
    _saturatedFat.show(n.saturatedFat100);
    _sugars.show(n.sugars100);
    _sodium.show(n.sodium100);
    _calcium.show(n.calcium100);
    _iron.show(n.iron100);
    _potassium.show(n.potassium100);
    _magnesium.show(n.magnesium100);
    _vitaminD.show(n.vitaminD100);
    _vitaminB12.show(n.vitaminB12100);
    _showMoreNutrients = _microFields.any((field) => field.value != null);
    if (_countBased) {
      // Stored per 100 of its units; one serving is [_countServing] of them.
      for (final field in _nutritionFields) {
        field.scale(_countServing / 100);
      }
    }
    _localImagePath = meal.localImagePath;
  }

  @override
  void dispose() {
    _nameTextController.dispose();
    _brandsTextController.dispose();
    _barcodeTextController.dispose();
    _serving.controller.removeListener(_onServingChanged);
    _serving.dispose();
    for (final field in _nutritionFields) {
      field.dispose();
    }
    // Do not close _editMealBloc here if provided as a singleton by locator.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the energy-unit provider so the form reacts when the user
    // flips between kcal and kJ in Settings while this screen is open.
    final usesKj = context.watch<EnergyUnitProvider>().usesKilojoules;
    _maybeReinterpretKcalField(usesKj);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final isNew = _newFood || (_mealEntity.name ?? '').trim().isEmpty;
    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: appBarHeightForTitle(context, titleLines: 2),
        title: Text(
          isNew
              ? S.of(context).customFoodNewTitle
              : S.of(context).customFoodEditTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Dimens.spacing16,
              0,
              Dimens.spacing16,
              0,
            ),
            child: Semantics(
              identifier: 'edit-meal-save',
              child: FilledButton(
                onPressed: () => _onSavePressed(_usesImperialUnits),
                style: FilledButton.styleFrom(
                  shape: const RoundedRectangleBorder(
                    borderRadius: Dimens.borderRadiusM,
                  ),
                ),
                child: Text(S.of(context).buttonSaveLabel),
              ),
            ),
          ),
        ],
      ),
      body: BlocBuilder<EditMealBloc, EditMealState>(
        bloc: _editMealBloc,
        builder: (BuildContext context, EditMealState state) {
          if (state is EditMealLoadingState) {
            return _getLoadingContent();
          } else if (state is EditMealLoadedState) {
            return _getLoadedContent(usesKj, palette);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  /// Re-interpret whatever the energy field holds when the active energy
  /// unit changes mid-edit, so it keeps meaning the same energy.
  void _maybeReinterpretKcalField(bool usesKj) {
    if (_lastRenderedUsesKj == null || _lastRenderedUsesKj == usesKj) {
      _lastRenderedUsesKj = usesKj;
      return;
    }
    _kcal.scale(usesKj ? UnitCalc.kcalToKjFactor : 1 / UnitCalc.kcalToKjFactor);
    _lastRenderedUsesKj = usesKj;
  }

  Widget _getLoadingContent() {
    return const Center(child: CircularProgressIndicator());
  }

  /// The serving in grams or millilitres, or null when none is set.
  double? get _servingMetric {
    if (_countBased) return null;
    final original = _mealEntity.scalableServingQuantity;
    if (_serving.isUnchanged && original != null) return original;
    final shown = _serving.value;
    if (shown == null || shown <= 0) return null;
    return _fromDisplayQuantity(shown);
  }

  double _toDisplayQuantity(double metric) {
    if (!_usesImperialUnits) return metric;
    return _unit == 'ml' ? UnitCalc.mlToFlOz(metric) : UnitCalc.gToOz(metric);
  }

  double _fromDisplayQuantity(double shown) {
    if (!_usesImperialUnits) return shown;
    return _unit == 'ml' ? UnitCalc.flOzToMl(shown) : UnitCalc.ozToG(shown);
  }

  String _unitLabel(BuildContext context, String unit) {
    final s = S.of(context);
    if (_usesImperialUnits) return unit == 'ml' ? s.flOzUnit : s.ozUnit;
    return unit == 'ml' ? s.milliliterUnit : s.gramUnit;
  }

  /// Switches the nutrition fields between per 100 and per serving, keeping
  /// what they describe: 50 kcal per 100 g is 100 kcal per 200 g serving.
  void _setBasis(_Basis basis) {
    if (basis == _basis) return;
    final serving = _servingMetric;
    if (serving == null) return;
    final factor = basis == _Basis.perServing ? serving / 100 : 100 / serving;
    setState(() {
      for (final field in _nutritionFields) {
        field.scale(factor);
      }
      _basis = basis;
    });
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: Dimens.spacing12),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
  );

  Widget _numberField(
    _NumberField field,
    String label, {
    String? suffix,
    String? helper,
    String? identifier,
  }) {
    // A pre-filled form points at the main values its source lacked.
    final missing =
        _prefilledFrom != null &&
        _mainFields.contains(field) &&
        field.controller.text.trim().isEmpty;
    final highlight = Theme.of(context).colorScheme.primary;
    final input = TextFormField(
      controller: field.controller,
      inputFormatters: CustomTextInputFormatter.doubleOnly(),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        helperText: missing ? S.of(context).customFoodMissingValue : helper,
        helperMaxLines: 3,
        helperStyle: missing ? TextStyle(color: highlight) : null,
        border: const OutlineInputBorder(borderRadius: Dimens.borderRadiusM),
        enabledBorder: missing
            ? OutlineInputBorder(
                borderRadius: Dimens.borderRadiusM,
                borderSide: BorderSide(color: highlight, width: 2),
              )
            : null,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Dimens.spacing16),
      child: identifier == null
          ? input
          : Semantics(identifier: identifier, child: input),
    );
  }

  Widget _getLoadedContent(bool usesKj, AppPalette palette) {
    final s = S.of(context);
    final energyUnit = usesKj ? s.kjLabel : s.kcalLabel;
    final hasServing = _servingMetric != null;
    final canPickPhoto =
        _mealEntity.source == MealSourceEntity.custom && !_snapshotOnly;
    final hasRemoteImage = _mealEntity.mainImageUrl?.isNotEmpty ?? false;
    return ListView(
      // The screen draws behind the navigation bar, so the last field
      // scrolls clear of it.
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        // Custom foods get the same picker tile recipes use. A logged copy
        // shares its photo file with the saved food, so it keeps its photo.
        if (canPickPhoto) ...[
          Center(
            child: UserImagePickerTile(
              kind: UserImageKind.meal,
              imagePath: _localImagePath,
              onPickFromGallery: () => _onPickMealImage(ImageSource.gallery),
              onTakePhoto: () => _onPickMealImage(ImageSource.camera),
              onRemove: _onRemoveMealImage,
            ),
          ),
          const SizedBox(height: 24),
        ] else if (hasRemoteImage) ...[
          Center(child: _buildRemoteMealImage()),
          const SizedBox(height: 24),
        ],
        if (_prefilledFrom != null) ...[
          Semantics(
            identifier: 'edit-meal-prefilled-note',
            child: AppCard(
              color: palette.surfaceMuted,
              padding: const EdgeInsets.all(Dimens.spacing12),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: palette.textMuted),
                  const SizedBox(width: Dimens.spacing12),
                  Expanded(
                    child: Text(
                      s.customFoodPrefilledNote(_prefilledFrom!),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.textStrong,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        TextFormField(
          controller: _nameTextController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: s.mealNameLabel,
            border: const OutlineInputBorder(
              borderRadius: Dimens.borderRadiusM,
            ),
          ),
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _brandsTextController,
          decoration: InputDecoration(
            labelText: s.mealBrandsLabel,
            border: const OutlineInputBorder(
              borderRadius: Dimens.borderRadiusM,
            ),
          ),
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 16),
        // Optional barcode (#167). Lets the user attach a code to a custom
        // meal so a future scan recalls the saved version directly without
        // round-tripping through Open Food Facts.
        Semantics(
          identifier: 'edit-meal-barcode-input',
          child: TextFormField(
            controller: _barcodeTextController,
            decoration: InputDecoration(
              labelText: s.customMealBarcodeLabel,
              hintText: s.customMealBarcodeHint,
              border: const OutlineInputBorder(
                borderRadius: Dimens.borderRadiusM,
              ),
              suffixIcon: Semantics(
                identifier: 'edit-meal-barcode-scan',
                child: IconButton(
                  tooltip: s.customMealBarcodeScanButton,
                  icon: const Icon(Icons.barcode_reader),
                  onPressed: _scanBarcodeIntoField,
                ),
              ),
            ),
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(height: 32),
        // The serving first: it says what the food is measured in, so the
        // nutrition below can be typed per 100 g or per serving.
        _sectionTitle(context, s.customFoodServingSection),
        if (_countBased)
          Padding(
            padding: const EdgeInsets.only(bottom: Dimens.spacing16),
            child: Text(
              s.customFoodCountedInServings,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
            ),
          )
        else ...[
          Semantics(
            identifier: 'edit-meal-unit-selector',
            child: SegmentedButton<String>(
              segments: [
                for (final unit in const ['g', 'ml'])
                  ButtonSegment(
                    value: unit,
                    label: Text(_unitLabel(context, unit)),
                  ),
              ],
              selected: {_unit},
              onSelectionChanged: (selection) =>
                  setState(() => _unit = selection.first),
            ),
          ),
          const SizedBox(height: 16),
          _numberField(
            _serving,
            s.customFoodServingSizeLabel,
            suffix: _unitLabel(context, _unit),
            helper: s.customFoodServingSizeHelper,
            identifier: 'edit-meal-serving-size',
          ),
        ],
        const SizedBox(height: 16),
        _sectionTitle(context, s.customFoodNutritionSection),
        if (!_countBased) ...[
          Semantics(
            identifier: 'edit-meal-nutrition-basis',
            child: SegmentedButton<_Basis>(
              segments: [
                ButtonSegment(
                  value: _Basis.per100,
                  label: Text(
                    s.customFoodPer100(
                      _unit == 'ml' ? s.milliliterUnit : s.gramUnit,
                    ),
                  ),
                ),
                ButtonSegment(
                  value: _Basis.perServing,
                  enabled: hasServing || _basis == _Basis.perServing,
                  label: Text(s.customFoodPerServing),
                ),
              ],
              selected: {_basis},
              onSelectionChanged: (selection) => _setBasis(selection.first),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _numberField(
          _kcal,
          '${s.mealEnergyLabel} ($energyUnit)',
          identifier: 'edit-meal-energy',
        ),
        _numberField(_carbs, s.mealCarbsLabel, suffix: s.gramUnit),
        _numberField(_fat, s.mealFatLabel, suffix: s.gramUnit),
        _numberField(_protein, s.mealProteinLabel, suffix: s.gramUnit),
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            identifier: 'edit-meal-more-nutrients',
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _showMoreNutrients = !_showMoreNutrients),
              icon: Icon(
                _showMoreNutrients
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(s.customFoodMoreNutrients),
            ),
          ),
        ),
        if (_showMoreNutrients) ...[
          const SizedBox(height: 8),
          _numberField(_fiber, s.fiberLabel, suffix: 'g'),
          _numberField(_saturatedFat, s.saturatedFatLabel, suffix: 'g'),
          _numberField(_sugars, s.sugarLabel, suffix: 'g'),
          _numberField(_sodium, s.sodiumLabel, suffix: 'mg'),
          _numberField(_calcium, s.calciumLabel, suffix: 'mg'),
          _numberField(_iron, s.ironLabel, suffix: 'mg'),
          _numberField(_potassium, s.potassiumLabel, suffix: 'mg'),
          _numberField(_magnesium, s.magnesiumLabel, suffix: 'mg'),
          _numberField(_vitaminD, s.vitaminDLabel, suffix: 'µg'),
          _numberField(_vitaminB12, s.vitaminB12Label, suffix: 'µg'),
        ],
        if (!_editOnly && !_snapshotOnly) ...[
          const SizedBox(height: 24),
          _SaveForLaterField(
            value: _saveForLater,
            onChanged: (newValue) {
              setState(() {
                _saveForLater = newValue;
              });
            },
          ),
        ],
      ],
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onSavePressed(bool usesImperialUnits) async {
    final s = S.of(context);
    try {
      // Validate meal name: non-empty and contains at least one letter (#211, #214)
      if (!FoodNameValidator.isValid(_nameTextController.text)) {
        _showError(s.mealNameValidationError);
        return;
      }

      // Validate barcode shape if the user typed or scanned one (#167).
      // Empty is fine — the field is optional. 8-14 digits required;
      // EAN-13 check digit must verify for codes of that exact length.
      final rawBarcode = _barcodeTextController.text.trim();
      if (rawBarcode.isNotEmpty) {
        if (!isBarcodeFormatValid(rawBarcode)) {
          _showError(s.customMealBarcodeInvalid);
          return;
        }
        if (!isEan13CheckDigitValid(rawBarcode)) {
          _showError(s.barcodeInvalidEan13CheckDigit);
          return;
        }
      }

      final serving = _servingMetric;
      final double factor;
      if (_countBased) {
        factor = 100 / _countServing;
      } else if (_basis == _Basis.perServing) {
        if (serving == null) {
          _showError(s.customFoodServingNeeded);
          return;
        }
        factor = 100 / serving;
      } else {
        factor = 1;
      }
      double? per100(_NumberField field) {
        final value = field.value;
        return value == null ? null : value * factor;
      }

      // The energy field is in the user's unit (#177 follow-up); storage is
      // kcal. A blank main value means none: plenty of foods have no fat or
      // no carbs, and a blank must not block logging the food later.
      final usesKj = Provider.of<EnergyUnitProvider>(
        context,
        listen: false,
      ).usesKilojoules;
      final energy = per100(_kcal) ?? 0;
      final kcal = usesKj ? UnitCalc.kjToKcal(energy) : energy;
      final carbs = per100(_carbs) ?? 0;
      final fat = per100(_fat) ?? 0;
      final protein = per100(_protein) ?? 0;

      // 100 g of food holds at most 100 g of nutrients, and no more energy
      // than pure fat. A food counted in servings has no weight to check.
      if (!_countBased) {
        for (final (value, label) in [
          (carbs, s.mealCarbsLabel),
          (fat, s.mealFatLabel),
          (protein, s.mealProteinLabel),
        ]) {
          if (value > 100.5) {
            _showError(s.customFoodNutrientTooHigh(label));
            return;
          }
        }
        if (carbs + fat + protein > 105) {
          _showError(s.customFoodMacrosTooHigh);
          return;
        }
        if (kcal > 905) {
          _showError(s.customFoodEnergyTooHigh);
          return;
        }
      }

      // Atwater consistency check (#213): warn if entered kcal disagrees
      // with 4·carbs + 4·protein + 9·fat by more than 5%. Non-blocking, and
      // only for values typed here, not ones the food already had.
      final expectedKcal = 4 * carbs + 4 * protein + 9 * fat;
      final delta = (kcal - expectedKcal).abs();
      final ceiling = math.max(kcal.abs(), expectedKcal.abs());
      final typed = [_kcal, _carbs, _fat, _protein].any((f) => !f.isUnchanged);
      if (typed && ceiling > 0 && delta > 0.05 * ceiling) {
        final shouldSaveAnyway = await _showAtwaterWarningDialog();
        if (!mounted) return;
        if (shouldSaveAnyway != true) return;
      }

      final newMealEntity = _editMealBloc.createNewMealEntity(
        _mealEntity,
        name: _nameTextController.text,
        brands: _brandsTextController.text,
        unit: _countBased ? null : _unit,
        servingQuantity: serving,
        per100: (
          kcal: kcal,
          carbs: carbs,
          fat: fat,
          protein: protein,
          fiber: per100(_fiber),
          saturatedFat: per100(_saturatedFat),
          sugars: per100(_sugars),
          sodium: per100(_sodium),
          calcium: per100(_calcium),
          iron: per100(_iron),
          potassium: per100(_potassium),
          magnesium: per100(_magnesium),
          vitaminD: per100(_vitaminD),
          vitaminB12: per100(_vitaminB12),
        ),
        barcodeOverride: rawBarcode.isEmpty ? null : rawBarcode,
        localImagePathOverride: _localImagePath,
        clearLocalImagePath: _localImageCleared && _localImagePath == null,
      );

      if (!mounted) return;
      // A logged copy changes only that diary entry, which its caller saves.
      if (_snapshotOnly) {
        Navigator.of(context).pop(newMealEntity);
        return;
      }

      // Persist custom meal template (#267). Skipped for one-off entries
      // (#249) when the user has turned off "Save for next time" — the
      // intake itself is still logged below, but no template is kept.
      final shouldPersistTemplate = _editOnly || _saveForLater;
      if (newMealEntity.source == MealSourceEntity.custom &&
          shouldPersistTemplate) {
        await _editMealBloc.saveCustomMeal(newMealEntity);
      }

      if (!mounted) return;
      if (_editOnly) {
        // Pop the saved meal rather than nothing. Callers that only wanted
        // the side effect (the Library list, the recipes page) ignore the
        // result exactly as before; the scanner's not-found flow needs it,
        // because in pick mode it has to hand the newly created food back
        // up to the recipe builder that asked for an ingredient.
        Navigator.of(context).pop(newMealEntity);
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil(
          NavigationOptions.mealDetailRoute,
          namedRouteOrFirst(NavigationOptions.addMealRoute),
          arguments: MealDetailScreenArguments(
            newMealEntity,
            _intakeTypeEntity,
            _day,
            usesImperialUnits,
          ),
        );
      }
    } catch (exception, stacktrace) {
      log.warning(
        "Error while creating new meal entity",
        exception,
        stacktrace,
      );

      if (!mounted) return;
      _showError(s.errorMealSave);
    }
  }

  /// Push a lightweight `ReaderWidget` page that returns the first product
  /// barcode it sees, then drop the value into the barcode TextField. The
  /// scan-time validator on the field handles bad codes (8–14 digits,
  /// EAN-13 check digit) — we don't double-validate here so the user can
  /// see and edit the raw scanned value before saving.
  Future<void> _scanBarcodeIntoField() async {
    log.fine('Opening edit-meal barcode scanner');
    final navigator = Navigator.of(context);
    final result = await navigator.push<String?>(
      MaterialPageRoute(builder: (_) => const _EditMealBarcodeScanPage()),
    );
    if (kDebugMode) log.fine('Edit-meal barcode scanner returned: $result');
    if (result == null) return;
    if (!mounted) return;
    setState(() {
      _barcodeTextController.text = result;
    });
    if (kDebugMode) {
      log.fine(
        'Barcode text controller after set: ${_barcodeTextController.text}',
      );
    }
  }

  Widget _buildRemoteMealImage() {
    return ClipOval(
      child: CachedNetworkImage(
        cacheManager: locator<CacheManager>(),
        width: 120,
        height: 120,
        placeholder: (context, string) => const DefaultMealImage(),
        errorWidget: (context, exception, stacktrace) =>
            const DefaultMealImage(),
        fit: BoxFit.cover,
        imageUrl: _mealEntity.mainImageUrl ?? "",
      ),
    );
  }

  Future<void> _onPickMealImage(ImageSource source) async {
    // For custom meals the entity's `code` is a stable UUID seeded at
    // MealEntity.empty() time; we use it as the photo's filename so a
    // re-edit of the same meal lands at the same on-disk slug. If the
    // user has typed a real barcode into the code field, fall back to
    // the entity's original code rather than the in-progress text — the
    // photo identity is the meal, not the barcode.
    final ownerId = _mealEntity.code;
    if (ownerId == null) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source);
      if (picked == null) return;
      final relative = await UserImageStorage.importFrom(
        kind: UserImageKind.meal,
        ownerId: ownerId,
        sourcePath: picked.path,
      );
      // Bust the in-memory Image.file cache so the new picture shows up
      // immediately instead of redrawing previous bytes for this path.
      FileImage(File(await UserImageStorage.absolutePath(relative))).evict();
      if (!mounted) return;
      setState(() {
        _localImagePath = relative;
        _localImageCleared = false;
      });
    } catch (e, st) {
      // Pick / encode failure is rare; surfacing a SnackBar from inside
      // the picker flow felt noisier than the failure deserves. The user
      // can simply tap the picker again.
      log.warning('Failed to pick meal image', e, st);
    }
  }

  Future<void> _onRemoveMealImage() async {
    final current = _localImagePath;
    if (current == null) return;
    await UserImageStorage.delete(current);
    if (!mounted) return;
    setState(() {
      _localImagePath = null;
      _localImageCleared = true;
    });
  }

  Future<bool?> _showAtwaterWarningDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(S.of(dialogContext).inconsistentNutritionWarningTitle),
          content: Text(S.of(dialogContext).inconsistentNutritionWarningBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(S.of(dialogContext).inconsistentNutritionWarningEdit),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                S.of(dialogContext).inconsistentNutritionWarningSaveAnyway,
              ),
            ),
          ],
        );
      },
    );
  }
}

class EditMealScreenArguments {
  final DateTime day;
  final MealEntity mealEntity;
  final IntakeTypeEntity intakeTypeEntity;
  final bool usesImperialUnits;
  final bool editOnly;

  /// Edits one logged copy: Save hands the edited food back to the caller
  /// and nothing is saved to the Library.
  final bool snapshotOnly;

  /// The food is new even though [mealEntity] arrives with a name — one
  /// found for a scanned code — so the form says "New food", not "Edit".
  final bool newFood;

  /// Names the source [mealEntity] was filled in from (METRO, Open Food
  /// Facts). The form then says so and highlights the main values the
  /// source lacked, for the user to copy from the label.
  final String? prefilledFrom;

  EditMealScreenArguments(
    this.day,
    this.mealEntity,
    this.intakeTypeEntity,
    this.usesImperialUnits, {
    this.editOnly = false,
    this.snapshotOnly = false,
    this.newFood = false,
    this.prefilledFrom,
  });
}

/// "Save for next time" toggle shown on the create-and-log path (#249).
/// Defaults to off: the intake is logged today, and the user opts in here
/// to also keep the meal as a reusable template in the custom-meal list.
/// Leaving it off is the right call for one-off entries like a friend's
/// homemade dish or a restaurant meal that won't come back round.
class _SaveForLaterField extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SaveForLaterField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return AppCard(
      color: palette.surfaceMuted,
      onTap: () => onChanged(!value),
      padding: const EdgeInsets.fromLTRB(
        Dimens.spacing8,
        Dimens.spacing12,
        Dimens.spacing16,
        Dimens.spacing12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            identifier: 'edit-meal-save-for-later',
            child: Checkbox(
              value: value,
              onChanged: (newValue) => onChanged(newValue ?? false),
            ),
          ),
          const SizedBox(width: Dimens.spacing4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: Dimens.spacing12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.recipeSaveForLaterLabel,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Dimens.spacing4),
                  Text(
                    s.recipeSaveForLaterDescription,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal camera page used by [_EditMealScreenState._scanBarcodeIntoField].
/// Pops itself with the first product barcode it detects, or returns null
/// when the user taps the back button. We keep this private to the edit-meal
/// flow rather than reusing the full ScannerScreen because that screen runs
/// its own lookup-and-route logic that wouldn't fit a "give me the raw
/// string" use case.
class _EditMealBarcodeScanPage extends StatefulWidget {
  const _EditMealBarcodeScanPage();

  @override
  State<_EditMealBarcodeScanPage> createState() =>
      _EditMealBarcodeScanPageState();
}

class _EditMealBarcodeScanPageState extends State<_EditMealBarcodeScanPage> {
  static final _log = Logger('EditMealBarcodeScan');
  bool _done = false;

  @override
  void initState() {
    super.initState();
    configureZxingLogging();
  }

  void _onScan(Code code) {
    if (kDebugMode) {
      _log.fine('onScan: ${code.text} (format=${code.format?.name})');
    }
    if (_done) return;
    // Accept any non-empty text, whatever the symbology. This screen fills a
    // free-text barcode field, so it deliberately does not restrict to the
    // retail formats the product scanner uses — the save-time validator on
    // the edit-meal screen does the real "is this a valid barcode" check.
    //
    // Under ML Kit this leniency was a workaround: its classifier labelled
    // valid retail barcodes as `BarcodeType.unknown` depending on print
    // quality. ZXing reports the symbology deterministically, so the leniency
    // is now a deliberate choice rather than a hedge.
    final raw = code.text;
    if (raw != null && raw.isNotEmpty) {
      _done = true;
      Navigator.of(context).pop(raw);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).customMealBarcodeScanButton)),
      body: ReaderWidget(
        onScan: _onScan,
        showGallery: false,
        // Same reasoning as the product scanner: the 0.5 default crops a
        // 1280x720 frame down to a 360 px square, which a retail barcode
        // overruns horizontally at normal scanning distance.
        cropPercent: 0.9,
        scanDelay: const Duration(milliseconds: 250),
        tryHarder: true,
      ),
    );
  }
}
