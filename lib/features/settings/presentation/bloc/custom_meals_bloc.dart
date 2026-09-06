import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/merge_custom_meals_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';

part 'custom_meals_event.dart';
part 'custom_meals_state.dart';

class CustomMealsBloc extends Bloc<CustomMealsEvent, CustomMealsState> {
  final log = Logger('CustomMealsBloc');

  final CustomMealDataSource _customMealDataSource;
  final GetIntakeUsecase _getIntakeUsecase;
  final DeleteIntakeUsecase _deleteIntakeUsecase;
  final AddTrackedDayUsecase _addTrackedDayUsecase;
  final MergeCustomMealsUseCase _mergeCustomMealsUseCase;

  CustomMealsBloc(
    this._customMealDataSource,
    this._getIntakeUsecase,
    this._deleteIntakeUsecase,
    this._addTrackedDayUsecase,
    this._mergeCustomMealsUseCase,
  ) : super(CustomMealsInitial()) {
    on<LoadCustomMealsEvent>((event, emit) async {
      emit(CustomMealsLoadingState());
      try {
        final meals = _customMealDataSource
            .getAllCustomMeals()
            .map(MealEntity.fromMealDBO)
            .toList();
        emit(CustomMealsLoadedState(meals: meals));
      } catch (error) {
        log.severe(error);
        emit(CustomMealsFailedState());
      }
    });

    on<DeleteCustomMealEvent>((event, emit) async {
      emit(CustomMealsLoadingState());
      try {
        // Remove the template from the dedicated custom meal box.
        await _customMealDataSource.deleteCustomMeal(event.mealKey);

        // The diary is only touched when the user explicitly asked for it.
        // Entries carry their own meal snapshot, so leaving them behind
        // costs nothing and keeps the log an honest record of what was
        // eaten — see [DeleteCustomMealEvent.deleteIntakes].
        if (event.deleteIntakes) {
          for (final intake in await _loggedEntriesFor(event.mealKey)) {
            await _deleteIntakeUsecase.deleteIntake(intake);
            await _addTrackedDayUsecase.removeDayCaloriesTracked(
              intake.dateTime,
              intake.totalKcal,
            );
            await _addTrackedDayUsecase.removeDayMacrosTracked(
              intake.dateTime,
              carbsTracked: intake.totalCarbsGram,
              fatTracked: intake.totalFatsGram,
              proteinTracked: intake.totalProteinsGram,
            );
          }
          _refreshIntakeScreens();
        }
        add(LoadCustomMealsEvent());
      } catch (error) {
        log.severe(error);
        emit(CustomMealsFailedState());
      }
    });

    on<UpdateCustomMealLibraryFlagsEvent>((event, emit) async {
      try {
        await _customMealDataSource.setLibraryFlags(
          event.meal,
          favorite: event.favorite,
          rescue: event.rescue,
        );
        final meals = _customMealDataSource
            .getAllCustomMeals()
            .map(MealEntity.fromMealDBO)
            .toList();
        emit(CustomMealsLoadedState(meals: meals));
      } catch (error) {
        log.severe(error);
        emit(CustomMealsFailedState());
      }
    });

    on<MergeCustomMealsEvent>((event, emit) async {
      emit(CustomMealsLoadingState());
      try {
        final result = await _mergeCustomMealsUseCase.merge(
          loserKey: event.loserKey,
          winnerKey: event.winnerKey,
        );
        final meals = _customMealDataSource
            .getAllCustomMeals()
            .map(MealEntity.fromMealDBO)
            .toList();
        _refreshIntakeScreens();
        emit(
          CustomMealsMergedState(
            meals: meals,
            rewrittenIntakeCount: result.rewrittenIntakeCount,
            winnerDisplayName: result.winnerDisplayName,
          ),
        );
      } catch (error) {
        log.severe(error);
        emit(CustomMealsFailedState());
      }
    });
  }

  /// The diary entries a deletion of [mealKey] would remove.
  ///
  /// Deliberately the *same* predicate the deletion itself uses, so the count
  /// shown in the confirmation can never promise more than the delete
  /// performs. Note `getCustomMealIntakes` matches on
  /// `meal.source == custom`, so entries logged against a Library item that
  /// kept a remote source (a favourited product, or one reached by
  /// connecting a barcode) are not counted — and are correspondingly left
  /// alone. That is the conservative direction to be wrong in.
  Future<List<IntakeEntity>> _loggedEntriesFor(String mealKey) async {
    final allCustom = await _getIntakeUsecase.getCustomMealIntakes();
    return allCustom
        .where((intake) => (intake.meal.code ?? intake.meal.name) == mealKey)
        .toList();
  }

  /// How many diary entries deleting [mealKey] would take with it. Drives the
  /// count in the confirmation dialog, and whether the destructive option is
  /// offered there at all.
  Future<int> countLoggedEntries(String mealKey) async =>
      (await _loggedEntriesFor(mealKey)).length;

  /// Tell the screens that render intakes that we just rewrote their data.
  ///
  /// Deleting a custom meal cascades into the diary — every intake that used
  /// it is removed and the tracked-day totals are decremented — and merging
  /// re-points intakes at the surviving meal. Neither of those screens is
  /// reading Hive live: Today, Diary and the calendar all hold their last
  /// loaded state in lazy-singleton blocs, so without this they keep showing
  /// entries that no longer exist on disk. The deleted rows then only vanish
  /// when something *else* forces a reload, which reads as the delete having
  /// silently taken extra entries with it.
  ///
  /// Guarded so a unit test can build this bloc without standing up the whole
  /// locator; the refresh is cosmetic and must not fail the delete itself.
  void _refreshIntakeScreens() {
    if (locator.isRegistered<HomeBloc>()) {
      locator<HomeBloc>().add(const LoadItemsEvent());
    }
    if (locator.isRegistered<DiaryBloc>()) {
      locator<DiaryBloc>().add(const LoadDiaryYearEvent());
    }
    if (locator.isRegistered<CalendarDayBloc>()) {
      locator<CalendarDayBloc>().add(RefreshCalendarDayEvent());
    }
  }
}
