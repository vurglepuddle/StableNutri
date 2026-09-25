import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/navigation_predicates.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The food screen's action bar: Add, or for a logged entry Save and
/// Remove. The amount itself is picked at the top of the screen.
class MealDetailBottomSheet extends StatefulWidget {
  final MealEntity product;
  final DateTime day;
  final IntakeTypeEntity intakeTypeEntity;
  final TextEditingController quantityTextController;
  final MealDetailBloc mealDetailBloc;

  /// Set for a logged entry, which is saved or removed instead of added.
  final VoidCallback? onSave;
  final VoidCallback? onRemove;

  /// The system navigation area below the sheet.
  final double bottomInset;

  const MealDetailBottomSheet({
    super.key,
    required this.product,
    required this.day,
    required this.intakeTypeEntity,
    required this.quantityTextController,
    required this.mealDetailBloc,
    this.onSave,
    this.onRemove,
    this.bottomInset = 0,
  });

  @override
  State<MealDetailBottomSheet> createState() => _MealDetailBottomSheetState();
}

class _MealDetailBottomSheetState extends State<MealDetailBottomSheet> {
  static final _buttonShape = FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(vertical: Dimens.spacing16),
    shape: const RoundedRectangleBorder(borderRadius: Dimens.borderRadiusM),
  );

  @override
  Widget build(BuildContext context) {
    final productMissingRequiredInfo = _hasRequiredProductInfoMissing();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final s = S.of(context);
    final onSave = widget.onSave;
    final onRemove = widget.onRemove;
    return BottomSheet(
      elevation: 0,
      onClosing: () {},
      enableDrag: false,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: palette.border, width: Dimens.hairline),
            ),
            color: palette.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(Dimens.radiusL),
              topRight: Radius.circular(Dimens.radiusL),
            ),
          ),
          // The Scaffold strips the bottom inset from its bottom sheet, so the
          // screen hands it over: without it the buttons sat under the
          // gesture bar.
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16.0,
                16.0,
                16.0,
                8.0 + widget.bottomInset,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onSave != null)
                    // Save fills the row; removal is a square beside it, the
                    // same height, so neither label ever wraps.
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Semantics(
                            identifier: 'meal-detail-remove',
                            child: Tooltip(
                              message: s.loggedFoodRemove,
                              child: OutlinedButton(
                                onPressed: onRemove,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.error,
                                  side: BorderSide(color: palette.border),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Dimens.spacing16,
                                  ),
                                  minimumSize: const Size(56, 56),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: Dimens.borderRadiusM,
                                  ),
                                ),
                                child: Icon(
                                  Icons.delete_outline_rounded,
                                  semanticLabel: s.loggedFoodRemove,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: Dimens.spacing12),
                          Expanded(
                            child: Semantics(
                              identifier: 'meal-detail-save',
                              child: FilledButton.icon(
                                onPressed: productMissingRequiredInfo
                                    ? null
                                    : onSave,
                                style: _buttonShape,
                                icon: const Icon(Icons.check_rounded),
                                label: Text(s.buttonSaveLabel),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Semantics(
                      identifier: 'meal-detail-add',
                      child: SizedBox(
                        width: double.infinity, // Make button full width
                        child: FilledButton.icon(
                          onPressed: !productMissingRequiredInfo
                              ? () {
                                  onAddButtonPressed(context);
                                }
                              : null,
                          style: _buttonShape,
                          icon: const Icon(Icons.add_rounded),
                          label: Text(s.addLabel),
                        ),
                      ),
                    ),
                  if (productMissingRequiredInfo)
                    Text(
                      s.missingProductInfo,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _hasRequiredProductInfoMissing() {
    final productNutriments = widget.product.nutriments;
    if (productNutriments.energyKcal100 == null ||
        productNutriments.carbohydrates100 == null ||
        productNutriments.fat100 == null ||
        productNutriments.proteins100 == null) {
      return true;
    } else {
      return false;
    }
  }

  Future<void> onAddButtonPressed(BuildContext context) async {
    // Validate quantity (#209, #210)
    final quantityText = widget.quantityTextController.text.replaceAll(
      ',',
      '.',
    );
    final quantity = double.tryParse(quantityText);

    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${S.of(context).quantityLabel} must be greater than 0',
          ),
        ),
      );
      return;
    }

    // Reasonable maximum limit per meal (#210)
    if (quantity > 10000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${S.of(context).quantityLabel} seems unrealistically high',
          ),
        ),
      );
      return;
    }

    // Check for duplicate additions (#212)
    final isDuplicate = await _checkForDuplicate(context);
    if (!context.mounted) return;
    if (isDuplicate) {
      final shouldAdd = await _showDuplicateDialog(context);
      if (!context.mounted) return;
      if (shouldAdd != true) return;
    }

    widget.mealDetailBloc.addIntake(
      context,
      widget.mealDetailBloc.state.selectedUnit,
      widget.mealDetailBloc.state.totalQuantityConverted,
      widget.intakeTypeEntity,
      widget.product,
      widget.day,
    );

    // Refresh Home Page
    locator<HomeBloc>().add(const LoadItemsEvent());

    // Refresh Diary Page - Pass the day to preserve selection (#154)
    locator<DiaryBloc>().add(const LoadDiaryYearEvent());
    locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());

    // Show snackbar and return to dashboard
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(S.of(context).infoAddedIntakeLabel)));
    Navigator.of(
      context,
    ).popUntil(namedRouteOrFirst(NavigationOptions.mainRoute));
  }

  // #212: Check if this meal was already added today for the same meal type
  Future<bool> _checkForDuplicate(BuildContext context) async {
    final getIntakeUsecase = locator<GetIntakeUsecase>();
    final List<IntakeEntity> todayIntakes;

    switch (widget.intakeTypeEntity) {
      case IntakeTypeEntity.breakfast:
        todayIntakes = await getIntakeUsecase.getBreakfastIntakeByDay(
          widget.day,
        );
        break;
      case IntakeTypeEntity.lunch:
        todayIntakes = await getIntakeUsecase.getLunchIntakeByDay(widget.day);
        break;
      case IntakeTypeEntity.dinner:
        todayIntakes = await getIntakeUsecase.getDinnerIntakeByDay(widget.day);
        break;
      case IntakeTypeEntity.snack:
        todayIntakes = await getIntakeUsecase.getSnackIntakeByDay(widget.day);
        break;
    }

    // Check if meal with same code or name already exists
    return todayIntakes.any(
      (intake) =>
          (widget.product.code != null &&
              intake.meal.code == widget.product.code) ||
          (widget.product.name != null &&
              intake.meal.name == widget.product.name),
    );
  }

  // #212: Show confirmation dialog for duplicate meals
  Future<bool?> _showDuplicateDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).warningLabel),
          content: Text(S.of(context).duplicateMealDialogContent),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(S.of(context).dialogCancelLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(S.of(context).addLabel),
            ),
          ],
        );
      },
    );
  }
}
