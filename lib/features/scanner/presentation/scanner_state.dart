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

  /// True while barcode-list.ru is being asked for a name. The not-found
  /// screen shows straight away and fills the name in when it arrives.
  final bool isLookingUpName;

  /// What barcode-list.ru calls this product; null when it does not know it,
  /// the lookup is off, or it has not answered yet.
  final String? suggestedName;

  const ScannerFailedState(
    this.type, {
    this.barcode = '',
    this.usesImperialUnits = false,
    this.isLookingUpName = false,
    this.suggestedName,
  });

  // props used to be const-empty, which made every failure state equal to
  // every other one — a switch from `error` to `productNotFound` would not
  // have rebuilt the screen.
  @override
  List<Object?> get props => [
    type,
    barcode,
    usesImperialUnits,
    isLookingUpName,
    suggestedName,
  ];
}

enum ScannerFailedStateType { productNotFound, error }
