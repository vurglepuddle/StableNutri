import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/macro_share_rings.dart';
import 'package:opennutritracker/core/presentation/widgets/meal_value_unit_text.dart';
import 'package:opennutritracker/core/presentation/widgets/image_full_screen.dart';
import 'package:opennutritracker/core/presentation/widgets/thumbnail_image.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_library_item_usecase.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/energy_display.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_quantity_units.dart';
import 'package:opennutritracker/features/edit_meal/presentation/edit_meal_screen.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/daily_kcal_overview.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_amount_picker.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_bottom_sheet.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_detail_nutriments_table.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_info_button.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_title_expanded.dart';
import 'package:opennutritracker/features/meal_detail/presentation/widgets/off_disclaimer.dart';
import 'package:opennutritracker/generated/l10n.dart';

class MealDetailScreen extends StatefulWidget {
  const MealDetailScreen({super.key});

  @override
  State<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  static const String _initialQuantityMetric = '100';
  static const String _initialQuantityImperial = '1';

  final log = Logger('ItemDetailScreen');

  late MealDetailBloc _mealDetailBloc;
  final _scrollController = ScrollController();

  // The toolbar shows the name once the large title has scrolled under it.
  final _titleKey = GlobalKey();
  final _showToolbarTitle = ValueNotifier(false);

  /// Measured height of the bottom sheet; the page pads its end by this.
  double _sheetHeight = 240;

  late MealEntity meal;
  late DateTime _day;
  late IntakeTypeEntity intakeTypeEntity;

  /// The diary entry being edited, or null when adding the food.
  IntakeEntity? _logged;

  /// The entry's amount as first shown; saved unchanged, it keeps its exact
  /// stored amount rather than the two decimals in the field.
  String? _loggedUnit;
  String? _loggedQuantity;

  /// Set while a save or removal is being written; a second tap would move
  /// the day's totals twice.
  bool _writing = false;

  final quantityTextController = TextEditingController();
  late bool _usesImperialUnits;
  bool _showMicronutrients = false;

  late String _selectedUnit;
  bool _initialized = false;
  bool _updatingSelection = false;

  bool _hydrationRequested = false;
  bool _libraryFlagsRequested = false;
  bool _userChangedSelection = false;

  @override
  void initState() {
    _mealDetailBloc = locator<MealDetailBloc>();
    _loadMicronutrientSetting();
    _scrollController.addListener(_onScroll);
    super.initState();
  }

  @override
  void dispose() {
    quantityTextController.dispose();
    _scrollController.dispose();
    _showToolbarTitle.dispose();
    super.dispose();
  }

  void _onScroll() {
    final titleHeight = _titleKey.currentContext?.size?.height ?? 0;
    _showToolbarTitle.value =
        titleHeight > 0 && _scrollController.offset > titleHeight - 8;
  }

  Future<void> _loadMicronutrientSetting() async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (mounted) {
      setState(() => _showMicronutrients = config.showMicronutrients);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args =
        ModalRoute.of(context)?.settings.arguments as MealDetailScreenArguments;
    meal = args.mealEntity;
    _day = args.day;
    intakeTypeEntity = args.intakeTypeEntity;
    _usesImperialUnits = args.usesImperialUnits;
    final logged = args.loggedIntake;
    _logged = logged;

    _mealDetailBloc.add(LoadDailyTotalsEvent(_day));

    if (logged != null) {
      // A logged entry keeps its own copy of the food, as it was logged.
      meal = logged.meal;
      intakeTypeEntity = logged.type;
      if (meal.source != MealSourceEntity.recipe) {
        _libraryFlagsRequested = true;
        _loadLibraryFlags();
      }
      _applyLoggedSelection(logged);
      return;
    }

    // Thin OFF search results get hydrated to the full product record (serving
    // fields + micronutrients) once, in the background; the listener in build()
    // swaps the displayed meal in when it arrives.
    if (!_hydrationRequested) {
      _hydrationRequested = true;
      _mealDetailBloc.add(HydrateMealEvent(meal));
    }
    if (!_libraryFlagsRequested && meal.source != MealSourceEntity.recipe) {
      _libraryFlagsRequested = true;
      _loadLibraryFlags();
    }

    _applyInitialSelection();
  }

  /// Pick the default unit and quantity from the meal's shape. Serving-based
  /// meals default to 1 serving; otherwise to 100 g/ml (or 1 oz/fl oz in
  /// imperial). Guarded so it only runs while the user hasn't chosen yet, and
  /// re-run after hydration reveals serving values.
  void _applyInitialSelection() {
    _selectedUnit = MealQuantityUnits(
      meal,
    ).defaultUnit(imperial: _usesImperialUnits);
    _setSelection(
      unit: _selectedUnit,
      amount: _selectedUnit == 'serving'
          ? '1'
          : _usesImperialUnits
          ? _initialQuantityImperial
          : _initialQuantityMetric,
    );
  }

  /// Shows a logged entry the way it was entered: 1.5 servings, 150 g or
  /// 5 oz. Entries store grams or millilitres, so the amount is converted
  /// back to the unit it was logged in.
  void _applyLoggedSelection(IntakeEntity intake) {
    final units = MealQuantityUnits(meal);
    var unit = MealQuantityUnits.canonical(intake.unit);
    final serving = meal.scalableServingQuantity;
    double? amount = switch (unit) {
      'serving' => serving == null ? null : intake.amount / serving,
      'oz' => UnitCalc.gToOz(intake.amount),
      'fl.oz' => UnitCalc.mlToFlOz(intake.amount),
      _ => intake.amount,
    };
    if (amount == null || !units.values.contains(unit)) {
      unit = units.values.contains(units.baseUnit) ? units.baseUnit : 'g/ml';
      amount = intake.amount;
    }
    final text = amount.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    _loggedUnit = unit;
    _loggedQuantity = text;
    _setSelection(unit: unit, amount: text);
  }

  // Update the controller and selected ID together before rebuilding the
  // dropdown. Controller notifications during hydration are not user edits.
  void _setSelection({required String unit, required String amount}) {
    _updatingSelection = true;
    _selectedUnit = unit;
    quantityTextController.text = amount;
    _updatingSelection = false;
    _mealDetailBloc.add(
      UpdateKcalEvent(meal: meal, selectedUnit: unit, totalQuantity: amount),
    );
  }

  /// Apply the hydrated full product to the screen. If the user hasn't touched
  /// the quantity/unit yet, re-pick the defaults (so serving becomes the
  /// default now that serving data exists); otherwise just recompute totals
  /// against the fuller nutriments while keeping the user's selection.
  void _onMealHydrated(MealEntity full) {
    final updated = full.copyWith(
      isFavorite: meal.isFavorite,
      isRescue: meal.isRescue,
    );
    final previousMeal = meal;
    meal = updated;
    if (updated.isFavorite || updated.isRescue) {
      unawaited(
        locator<UpdateLibraryItemUsecase>().updateMeal(
          updated,
          favorite: updated.isFavorite,
          rescue: updated.isRescue,
        ),
      );
    }
    if (_userChangedSelection) {
      final selection = MealQuantityUnits(meal).reconcile(
        _selectedUnit,
        quantityTextController.text,
        previousMeal: previousMeal,
      );
      _setSelection(unit: selection.unit, amount: selection.amount);
    } else {
      _applyInitialSelection();
    }
    setState(() {});
  }

  Future<void> _loadLibraryFlags() async {
    final saved = locator<UpdateLibraryItemUsecase>().getSavedMeal(meal);
    if (saved != null && mounted) {
      final updated = meal.copyWith(
        isFavorite: saved.isFavorite,
        isRescue: saved.isRescue,
      );
      setState(() => meal = updated);
      // A logged entry is an older copy: it must not replace the Library's.
      if (_logged != null) return;
      // If hydration already supplied a fuller remote record, refresh the
      // saved Library snapshot without changing either user label.
      unawaited(
        locator<UpdateLibraryItemUsecase>().updateMeal(
          updated,
          favorite: updated.isFavorite,
          rescue: updated.isRescue,
        ),
      );
    }
  }

  Future<void> _updateLibraryFlags({bool? favorite, bool? rescue}) async {
    final library = locator<UpdateLibraryItemUsecase>();
    final isFavorite = favorite ?? meal.isFavorite;
    final isRescue = rescue ?? meal.isRescue;
    if (_logged != null) {
      // Label the Library's own copy when there is one; the logged copy is
      // saved only when the food is not in the Library yet.
      await library.updateMeal(
        library.getSavedMeal(meal) ?? meal,
        favorite: isFavorite,
        rescue: isRescue,
      );
      if (mounted) {
        setState(
          () =>
              meal = meal.copyWith(isFavorite: isFavorite, isRescue: isRescue),
        );
      }
      return;
    }
    final updated = await library.updateMeal(
      meal,
      favorite: isFavorite,
      rescue: isRescue,
    );
    if (mounted) setState(() => meal = updated);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MealDetailBloc, MealDetailState>(
      bloc: _mealDetailBloc,
      listenWhen: (prev, curr) =>
          curr.hydratedMeal != null && curr.hydratedMeal != prev.hydratedMeal,
      listener: (context, state) => _onMealHydrated(state.hydratedMeal!),
      // The Scaffold paints behind the system bars like the rest of the app;
      // wrapping it left those strips showing the dark window. The bottom
      // sheet keeps its Add button clear of the navigation bar itself.
      child: Scaffold(
        backgroundColor:
            (Theme.of(context).brightness == Brightness.dark
                    ? AppPalette.dark
                    : AppPalette.light)
                .canvas,
        body: BlocBuilder<MealDetailBloc, MealDetailState>(
          bloc: _mealDetailBloc,
          builder: (context, state) {
            if (state is MealDetailInitial) {
              return _getLoadedContent(
                context,
                state.totalQuantityConverted,
                state.totalKcal,
                state.totalCarbs,
                state.totalFat,
                state.totalProtein,
                state.selectedUnit,
                state.dayKcalConsumed,
                state.dayKcalGoal,
                state.isHydrating,
              );
            }
            return const Center(child: CircularProgressIndicator());
          },
        ),
        bottomSheet: _MeasureSize(
          onChange: (size) {
            if (mounted && size.height != _sheetHeight) {
              setState(() => _sheetHeight = size.height);
            }
          },
          child: MealDetailBottomSheet(
            product: meal,
            day: _day,
            intakeTypeEntity: intakeTypeEntity,
            mealDetailBloc: _mealDetailBloc,
            quantityTextController: quantityTextController,
            onSave: _logged == null ? null : _saveLoggedEntry,
            onRemove: _logged == null ? null : _removeLoggedEntry,
            bottomInset: MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ),
    );
  }

  Widget _getLoadedContent(
    BuildContext context,
    String totalQuantity,
    double totalKcal,
    double totalCarbs,
    double totalFat,
    double totalProtein,
    String selectedUnit,
    double dayKcalConsumed,
    double dayKcalGoal,
    bool isHydrating,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // A plain toolbar over a header sized to its content. The previous
        // fixed-height collapsing header pinned the title to its bottom edge:
        // long names and larger text were squeezed into the day total and
        // clipped, with empty space above.
        SliverAppBar(
          pinned: true,
          backgroundColor: palette.surface,
          surfaceTintColor: Colors.transparent,
          title: ValueListenableBuilder<bool>(
            valueListenable: _showToolbarTitle,
            builder: (context, show, _) => AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                meal.name ?? '',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          actions: [
            // The rescue toggle is off this toolbar for now: it crowded the
            // title. Its new place is still to be decided.
            if (meal.source != MealSourceEntity.recipe) ...[
              IconButton(
                tooltip: meal.isFavorite
                    ? S.of(context).libraryRemoveFavorite
                    : S.of(context).libraryAddFavorite,
                onPressed: () =>
                    _updateLibraryFlags(favorite: !meal.isFavorite),
                icon: Icon(
                  meal.isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: meal.isFavorite
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            ],
            Semantics(
              identifier: 'meal-detail-edit',
              child: IconButton(
                onPressed: _logged != null
                    ? _editLoggedFood
                    : () {
                        Navigator.of(context).pushNamed(
                          NavigationOptions.editMealRoute,
                          arguments: EditMealScreenArguments(
                            _day,
                            meal,
                            intakeTypeEntity,
                            _usesImperialUnits,
                          ),
                        );
                      },
                icon: const Icon(Icons.edit_rounded),
              ),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: ColoredBox(
            color: palette.surface,
            child: Column(
              children: [
                MealTitleExpanded(
                  key: _titleKey,
                  meal: meal,
                  usesImperialUnits: _usesImperialUnits,
                ),
                DailyKcalOverview(
                  // A logged entry is already in the day's total.
                  dayKcalConsumed: math.max(
                    0,
                    dayKcalConsumed - (_logged?.totalKcal ?? 0),
                  ),
                  dayKcalGoal: dayKcalGoal,
                  currentSelectionKcal: totalKcal,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Dimens.spacing16,
                    Dimens.spacing12,
                    Dimens.spacing16,
                    Dimens.spacing16,
                  ),
                  child: MealAmountPicker(
                    product: meal,
                    quantityTextController: quantityTextController,
                    selectedUnit: _selectedUnit,
                    enabled: !_missingRequiredInfo,
                    intakeType: intakeTypeEntity,
                    onQuantityOrUnitChanged: onQuantityOrUnitChanged,
                    onIntakeTypeChanged: (type) =>
                        setState(() => intakeTypeEntity = type),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Wraps at large text instead of running off the edge.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Text(
                        EnergyDisplay.formatWithUnit(context, totalKcal),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      MealValueUnitText(
                        value: double.parse(totalQuantity),
                        meal: meal,
                        displayUnit:
                            selectedUnit == UnitDropdownItem.serving.toString()
                            ? meal.servingUnit
                            : selectedUnit,
                        usesImperialUnits: _usesImperialUnits,
                        textStyle: Theme.of(context).textTheme.bodyMedium,
                        prefix: ' / ',
                      ),
                    ],
                  ),
                  const SizedBox(height: Dimens.spacing16),
                  // How much of the energy each macro brings, and its grams.
                  MacroShareRings(
                    carbs: totalCarbs,
                    fat: totalFat,
                    protein: totalProtein,
                  ),
                  // No photo, no placeholder: an empty frame only took up room.
                  if (_hasPhoto) ...[
                    const SizedBox(height: Dimens.spacing24),
                    Center(child: _buildPhoto(context)),
                  ],
                  const SizedBox(height: Dimens.spacing24),
                  Divider(color: palette.border, height: Dimens.hairline),
                  const SizedBox(height: Dimens.spacing24),
                  if (isHydrating)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16.0),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  MealDetailNutrimentsTable(
                    product: meal,
                    usesImperialUnits: _usesImperialUnits,
                    servingQuantity: meal.servingQuantity,
                    servingUnit: meal.servingUnit,
                    showMicronutrients: _showMicronutrients,
                  ),
                  const SizedBox(height: 32.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: MealInfoButton(
                          url: meal.url,
                          source: meal.source,
                          backendSource: meal.backendSource,
                        ),
                      ),
                      if (meal.source == MealSourceEntity.off)
                        const OffDisclaimer(),
                    ],
                  ),
                  // The bottom sheet covers the end of the page; this lets the
                  // last row scroll fully above it, at any text size.
                  SizedBox(height: _sheetHeight + Dimens.spacing16),
                ],
              ),
            ),
          ]),
        ),
      ],
    );
  }

  void onQuantityOrUnitChanged(String? quantityString, String? unit) {
    if (_updatingSelection || quantityString == null || unit == null) {
      return;
    }
    _userChangedSelection = true;
    setState(() => _selectedUnit = unit);
    _mealDetailBloc.add(
      UpdateKcalEvent(
        meal: meal,
        totalQuantity: quantityString,
        selectedUnit: unit,
      ),
    );
  }

  bool get _missingRequiredInfo {
    final n = meal.nutriments;
    return n.energyKcal100 == null ||
        n.carbohydrates100 == null ||
        n.fat100 == null ||
        n.proteins100 == null;
  }

  /// Edits this entry's own copy of the food. The Library and other
  /// entries keep theirs.
  Future<void> _editLoggedFood() async {
    final edited = await Navigator.of(context).pushNamed<Object?>(
      NavigationOptions.editMealRoute,
      arguments: EditMealScreenArguments(
        _day,
        meal,
        intakeTypeEntity,
        _usesImperialUnits,
        snapshotOnly: true,
      ),
    );
    if (edited is! MealEntity || !mounted) return;
    final previous = meal;
    setState(() => meal = edited);
    final selection = MealQuantityUnits(meal).reconcile(
      _selectedUnit,
      quantityTextController.text,
      previousMeal: previous,
    );
    _setSelection(unit: selection.unit, amount: selection.amount);
  }

  void _showQuantityError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveLoggedEntry() async {
    final logged = _logged;
    if (logged == null) return;
    final state = _mealDetailBloc.state;
    final s = S.of(context);
    final untouched =
        state.selectedUnit == _loggedUnit &&
        quantityTextController.text == _loggedQuantity &&
        meal.scalableServingQuantity == logged.meal.scalableServingQuantity;
    final amount = untouched
        ? logged.amount
        : double.tryParse(state.totalQuantityConverted);
    final typed = double.tryParse(
      quantityTextController.text.replaceAll(',', '.'),
    );
    // Validate quantity (#209, #210)
    if (amount == null || amount <= 0 || typed == null || typed <= 0) {
      _showQuantityError('${s.quantityLabel} must be greater than 0');
      return;
    }
    if (typed > 10000) {
      _showQuantityError('${s.quantityLabel} seems unrealistically high');
      return;
    }
    if (_writing) return;
    _writing = true;
    final updated = IntakeEntity(
      id: logged.id,
      unit: state.selectedUnit,
      amount: amount,
      type: intakeTypeEntity,
      meal: meal,
      dateTime: logged.dateTime,
    );
    final home = locator<HomeBloc>();
    await home.replaceIntakeItem(logged, updated);
    home.add(const LoadItemsEvent());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s.loggedFoodSaved)));
    Navigator.of(context).pop();
  }

  /// Removes the entry from its day only; the food stays wherever else it
  /// is saved. Undo puts it back.
  Future<void> _removeLoggedEntry() async {
    final logged = _logged;
    if (logged == null || _writing) return;
    _writing = true;
    final home = locator<HomeBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    await home.deleteIntakeItem(logged);
    home.add(const LoadItemsEvent());
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.loggedFoodRemoved),
        persist: false,
        action: SnackBarAction(
          label: s.loggedFoodUndo,
          onPressed: () async {
            await home.restoreIntakeItem(logged);
            home.add(const LoadItemsEvent());
          },
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  bool get _hasPhoto =>
      meal.localImagePath != null || (meal.mainImageUrl?.isNotEmpty ?? false);

  /// The user's own photo, or the product image, which opens full screen.
  Widget _buildPhoto(BuildContext context) {
    final url = meal.mainImageUrl;
    final canOpen = meal.localImagePath == null && (url?.isNotEmpty ?? false);
    return GestureDetector(
      onTap: canOpen
          ? () => Navigator.of(context).pushNamed(
              NavigationOptions.imageFullScreenRoute,
              arguments: ImageFullScreenArguments(url!),
            )
          : null,
      child: Hero(
        tag: ImageFullScreen.fullScreenHeroTag,
        child: ThumbnailImage(
          localPath: meal.localImagePath,
          url: url,
          size: 250,
          // The user's photo fills a soft squircle; a product image sits
          // whole on a card, where so round a corner would crowd it.
          borderRadius: BorderRadius.circular(
            meal.localImagePath != null ? 80 : Dimens.radiusXL,
          ),
          fallback: const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Reports its child's size after layout, whenever it changes.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureSize renderObject,
  ) => renderObject.onChange = onChange;
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final current = size;
    if (current == _reported) return;
    _reported = current;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(current));
  }
}

class MealDetailScreenArguments {
  final MealEntity mealEntity;
  final IntakeTypeEntity intakeTypeEntity;
  final DateTime day;
  final bool usesImperialUnits;

  /// A diary entry to edit instead of adding [mealEntity]: the screen opens
  /// on its amount and meal, and saves or removes it.
  final IntakeEntity? loggedIntake;

  MealDetailScreenArguments(
    this.mealEntity,
    this.intakeTypeEntity,
    this.day,
    this.usesImperialUnits, {
    this.loggedIntake,
  });
}
