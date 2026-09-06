part of 'scanner_bloc.dart';

@immutable
abstract class ScannerEvent extends Equatable {
  const ScannerEvent();

  @override
  List<Object?> get props => [];
}

class ScannerLoadProductEvent extends ScannerEvent {
  final String barcode;

  const ScannerLoadProductEvent({required this.barcode});

  @override
  List<Object?> get props => [barcode];
}

/// Drops back to the camera preview after a failed lookup, so the user can
/// point at a different code without leaving and re-entering the scanner.
class ScannerResetEvent extends ScannerEvent {
  const ScannerResetEvent();
}
