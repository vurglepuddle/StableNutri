part of 'home_bloc.dart';

abstract class HomeEvent extends Equatable {
  const HomeEvent();

  @override
  List<Object?> get props => [];
}

class LoadItemsEvent extends HomeEvent {
  /// Hides the current dashboard until the reload finishes. Only for a
  /// different or wiped profile, whose old totals must not stay on screen.
  final bool reset;

  const LoadItemsEvent({this.reset = false});

  @override
  List<Object?> get props => [reset];
}
