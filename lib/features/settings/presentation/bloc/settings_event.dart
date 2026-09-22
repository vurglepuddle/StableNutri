part of 'settings_bloc.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();
}

class LoadSettingsEvent extends SettingsEvent {
  /// Hides the current settings until the reload finishes. Only for another
  /// or wiped profile, whose old values must not stay on screen.
  final bool reset;

  const LoadSettingsEvent({this.reset = false});

  @override
  List<Object?> get props => [reset];
}
