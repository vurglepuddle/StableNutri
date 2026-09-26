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
  /// Which source is being asked, for the words under the spinner.
  final BarcodeLookupStage stage;

  const ScannerLoadingState({this.stage = BarcodeLookupStage.local});

  @override
  List<Object?> get props => [stage];
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

  /// What the product is called: from [partial] when there is one,
  /// otherwise from barcode-list.ru. Null when nobody knows, the lookup is
  /// off, or it has not answered yet.
  final String? suggestedName;

  /// The product without (all of) its nutrition — an Open Food Facts record
  /// with no values, or a METRO product missing some. Seeds the new food.
  final MealEntity? partial;

  /// True while METRO is being searched by [suggestedName].
  final bool isSearchingMetro;

  /// METRO products that may be this one, best first, for the user to pick
  /// from. Each already carries [barcode].
  final List<MealEntity> metroMatches;

  const ScannerFailedState(
    this.type, {
    this.barcode = '',
    this.usesImperialUnits = false,
    this.isLookingUpName = false,
    this.suggestedName,
    this.partial,
    this.isSearchingMetro = false,
    this.metroMatches = const [],
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
    partial,
    isSearchingMetro,
    metroMatches,
  ];
}

enum ScannerFailedStateType { productNotFound, error }
