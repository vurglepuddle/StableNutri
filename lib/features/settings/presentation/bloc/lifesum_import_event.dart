part of 'lifesum_import_bloc.dart';

enum LifesumImportCategory {
  food,
  activity,
  weight,
  bodyMeasurements,
  estimatedWater,
}

sealed class LifesumImportEvent extends Equatable {
  const LifesumImportEvent();
}

class ChooseLifesumArchiveEvent extends LifesumImportEvent {
  const ChooseLifesumArchiveEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

class SetLifesumImportCategoryEvent extends LifesumImportEvent {
  const SetLifesumImportCategoryEvent({
    required this.category,
    required this.included,
  });

  final LifesumImportCategory category;
  final bool included;

  @override
  List<Object?> get props => <Object?>[category, included];
}

class ConfirmLifesumImportEvent extends LifesumImportEvent {
  const ConfirmLifesumImportEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

class ResetLifesumImportEvent extends LifesumImportEvent {
  const ResetLifesumImportEvent();

  @override
  List<Object?> get props => const <Object?>[];
}
