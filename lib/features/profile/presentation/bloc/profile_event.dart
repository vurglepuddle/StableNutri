part of 'profile_bloc.dart';

abstract class ProfileEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadProfileEvent extends ProfileEvent {
  /// Hides the current profile until the reload finishes. Only for another
  /// or wiped profile, whose old details must not stay on screen.
  final bool reset;

  LoadProfileEvent({this.reset = false});

  @override
  List<Object?> get props => [reset];
}
