import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/scanner/data/product_not_found_exception.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/look_up_barcode_name_usecase.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/search_product_by_barcode_usecase.dart';

part 'scanner_event.dart';

part 'scanner_state.dart';

class ScannerBloc extends Bloc<ScannerEvent, ScannerState> {
  final SearchProductByBarcodeUseCase _searchProductUseCase;
  final GetConfigUsecase _getConfigUsecase;

  /// Optional so a bloc built without it simply skips the name lookup.
  final LookUpBarcodeNameUseCase? _lookUpBarcodeNameUseCase;

  ScannerBloc(
    this._searchProductUseCase,
    this._getConfigUsecase, {
    LookUpBarcodeNameUseCase? lookUpBarcodeNameUseCase,
  }) : _lookUpBarcodeNameUseCase = lookUpBarcodeNameUseCase,
       super(ScannerInitial()) {
    on<ScannerLoadProductEvent>((event, emit) async {
      emit(ScannerLoadingState());

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
        );
        emit(
          ScannerLoadedState(
            product: meal,
            usesImperialUnits: usesImperialUnits,
          ),
        );
      } on ProductNotFoundException {
        // This used to be `if (exception == ProductNotFoundException)` inside
        // a bare catch, which compares the caught *instance* against the
        // *Type* object and is therefore never true. Every 404 fell through
        // to the generic "couldn't fetch" error, so the not-found branch —
        // and the add-a-barcode flow hanging off it — was unreachable. An
        // `on` clause types the match properly.
        final lookUpName = _lookUpBarcodeNameUseCase;
        emit(
          ScannerFailedState(
            ScannerFailedStateType.productNotFound,
            barcode: event.barcode,
            usesImperialUnits: usesImperialUnits,
            isLookingUpName: lookUpName != null,
          ),
        );
        if (lookUpName == null) return;

        // The screen is already up; the name fills in when it arrives. A
        // failed lookup only means no suggestion.
        String? suggestedName;
        try {
          suggestedName = (await lookUpName.lookUp(event.barcode))?.bestName;
        } catch (_) {}
        emit(
          ScannerFailedState(
            ScannerFailedStateType.productNotFound,
            barcode: event.barcode,
            usesImperialUnits: usesImperialUnits,
            suggestedName: suggestedName,
          ),
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
}
