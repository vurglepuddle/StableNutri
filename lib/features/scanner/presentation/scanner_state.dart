part of 'scanner_bloc.dart';

@immutable
abstract class ScannerState extends Equatable {
  const ScannerState();
}

class ScannerInitial extends ScannerState {
  @override
  List<Object> get props => [];
}

class ScannerLoadingState extends ScannerState {
  @override
  List<Object?> get props => [];
}

class ScannerLoadedState extends ScannerState {
  final MealEntity product;
  final bool usesImperialUnits;

  const ScannerLoadedState({
    required this.product,
    this.usesImperialUnits = false,
  });

  @override
  List<Object?> get props => [product];
}

class ScannerFailedState extends ScannerState {
  final ScannerFailedStateType type;

  /// The code that failed to resolve. The not-found screen needs it to seed
  /// the create-food form and to stamp onto an existing item, so it travels
  /// with the state rather than being read back off the screen.
  final String barcode;

  /// Carried through from config so the not-found screen can hand it to the
  /// custom-meal form without a second config round-trip.
  final bool usesImperialUnits;

  const ScannerFailedState(
    this.type, {
    this.barcode = '',
    this.usesImperialUnits = false,
  });

  // props used to be const-empty, which made every failure state equal to
  // every other one — a switch from `error` to `productNotFound` would not
  // have rebuilt the screen.
  @override
  List<Object?> get props => [type, barcode, usesImperialUnits];
}

enum ScannerFailedStateType { productNotFound, error }
