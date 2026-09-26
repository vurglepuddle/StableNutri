import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/scanner/data/product_not_found_exception.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/find_metro_matches_usecase.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/look_up_barcode_name_usecase.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/search_product_by_barcode_usecase.dart';

part 'scanner_event.dart';

part 'scanner_state.dart';

class ScannerBloc extends Bloc<ScannerEvent, ScannerState> {
  final SearchProductByBarcodeUseCase _searchProductUseCase;
  final GetConfigUsecase _getConfigUsecase;

  /// Optional so a bloc built without them simply skips those lookups.
  final LookUpBarcodeNameUseCase? _lookUpBarcodeNameUseCase;
  final FindMetroMatchesUseCase? _findMetroMatchesUseCase;

  ScannerBloc(
    this._searchProductUseCase,
    this._getConfigUsecase, {
    LookUpBarcodeNameUseCase? lookUpBarcodeNameUseCase,
    FindMetroMatchesUseCase? findMetroMatchesUseCase,
  }) : _lookUpBarcodeNameUseCase = lookUpBarcodeNameUseCase,
       _findMetroMatchesUseCase = findMetroMatchesUseCase,
       super(ScannerInitial()) {
    on<ScannerLoadProductEvent>((event, emit) async {
      emit(const ScannerLoadingState());

      // Config is read up front because both outcomes need it: a hit routes
      // into meal detail, and a miss routes into the custom-meal creation
      // form — which renders its quantity fields in the user's chosen units
      // just the same.
      var usesImperialUnits = false;

      try {
        final config = await _getConfigUsecase.getConfig();
        usesImperialUnits = config.usesImperialFoodUnits;

        final meal = await _searchProductUseCase.searchProductByBarcode(
          event.barcode,
          onStage: (stage) {
            if (!emit.isDone) emit(ScannerLoadingState(stage: stage));
          },
        );
        emit(
          ScannerLoadedState(
            product: meal,
            usesImperialUnits: usesImperialUnits,
          ),
        );
      } on ProductNotFoundException catch (notFound) {
        // This used to be `if (exception == ProductNotFoundException)` inside
        // a bare catch, which compares the caught *instance* against the
        // *Type* object and is therefore never true. Every 404 fell through
        // to the generic "couldn't fetch" error, so the not-found branch —
        // and the add-a-barcode flow hanging off it — was unreachable. An
        // `on` clause types the match properly.
        await _helpWithUnknown(
          emit,
          event.barcode,
          usesImperialUnits,
          notFound.partial,
        );
      } catch (exception) {
        emit(
          ScannerFailedState(
            ScannerFailedStateType.error,
            barcode: event.barcode,
            usesImperialUnits: usesImperialUnits,
          ),
        );
      }
    });

    // "Scan again" from the not-found screen. Returning to [ScannerInitial]
    // is what puts the camera preview back on screen; the screen clears its
    // own latched barcode alongside this so the next decode is accepted.
    on<ScannerResetEvent>((event, emit) => emit(ScannerInitial()));
  }

  /// The not-found screen shows at once; a name, then METRO's guesses by
  /// that name, fill in as they arrive. Each lookup is a bonus: a failure
  /// only means it adds nothing.
  Future<void> _helpWithUnknown(
    Emitter<ScannerState> emit,
    String barcode,
    bool usesImperialUnits,
    MealEntity? partial,
  ) async {
    final knownName = partial?.name?.trim();
    final nameLookUp = knownName == null || knownName.isEmpty
        ? _lookUpBarcodeNameUseCase
        : null;
    final findMatches = _findMetroMatchesUseCase;

    ScannerFailedState state({
      required String? name,
      required bool lookingUpName,
      required bool searchingMetro,
      List<MealEntity> matches = const [],
    }) => ScannerFailedState(
      ScannerFailedStateType.productNotFound,
      barcode: barcode,
      usesImperialUnits: usesImperialUnits,
      suggestedName: name,
      partial: partial,
      isLookingUpName: lookingUpName,
      isSearchingMetro: searchingMetro,
      metroMatches: matches,
    );

    var name = nameLookUp == null ? knownName : null;
    emit(
      state(
        name: name,
        lookingUpName: nameLookUp != null,
        // METRO is searched by name, so only once there is one to come.
        searchingMetro:
            findMatches != null && (name != null || nameLookUp != null),
      ),
    );

    if (nameLookUp != null) {
      try {
        name = (await nameLookUp.lookUp(barcode))?.bestName;
      } catch (_) {}
      emit(
        state(
          name: name,
          lookingUpName: false,
          searchingMetro: findMatches != null && name != null,
        ),
      );
    }

    if (findMatches == null || name == null) return;
    var matches = const <MealEntity>[];
    try {
      matches = await findMatches.find(
        name,
        barcode: barcode,
        excludeUrl: partial?.url,
      );
    } catch (_) {}
    emit(
      state(
        name: name,
        lookingUpName: false,
        searchingMetro: false,
        matches: matches,
      ),
    );
  }
}
