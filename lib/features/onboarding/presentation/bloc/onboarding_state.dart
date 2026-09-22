part of 'onboarding_bloc.dart';

abstract class OnboardingState extends Equatable {
  const OnboardingState();
}

class OnboardingInitialState extends OnboardingState {
  @override
  List<Object> get props => [];
}

class OnboardingLoadingState extends OnboardingState {
  @override
  List<Object?> get props => [];
}

class OnboardingLoadedState extends OnboardingState {
  final UserDataMaskEntity selection;

  const OnboardingLoadedState(this.selection);

  @override
  List<Object?> get props => [selection];
}
