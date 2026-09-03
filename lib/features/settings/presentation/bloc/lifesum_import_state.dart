part of 'lifesum_import_bloc.dart';

enum LifesumImportErrorKind {
  invalidArchive,
  profileChanged,
  previewChanged,
  confirmationExpired,
  rolledBack,
  importFailed,
}

sealed class LifesumImportState extends Equatable {
  const LifesumImportState();
}

class LifesumImportInitial extends LifesumImportState {
  const LifesumImportInitial();

  @override
  List<Object?> get props => const <Object?>[];
}

class LifesumImportLoading extends LifesumImportState {
  const LifesumImportLoading();

  @override
  List<Object?> get props => const <Object?>[];
}

class LifesumImportReady extends LifesumImportState {
  const LifesumImportReady({
    required this.preparation,
    required this.selection,
  });

  final LifesumImportPreparation preparation;
  final LifesumImportSelection selection;

  int get selectedOperationCount => preparation.operationCountFor(selection);

  @override
  List<Object?> get props => <Object?>[
    preparation,
    selection.includeFood,
    selection.includeActivity,
    selection.includeWeights,
    selection.includeBodyMeasurements,
    selection.includeEstimatedWater,
  ];
}

class LifesumImportApplying extends LifesumImportState {
  const LifesumImportApplying({
    required this.preparation,
    required this.selection,
  });

  final LifesumImportPreparation preparation;
  final LifesumImportSelection selection;

  @override
  List<Object?> get props => <Object?>[preparation, selection];
}

class LifesumImportSuccess extends LifesumImportState {
  const LifesumImportSuccess(this.journal);

  final LifesumImportJournal journal;

  int get addedCount =>
      journal.countFor(LifesumImportOperationProgress.applied);
  int get keptCount =>
      journal.countFor(LifesumImportOperationProgress.preserved);

  @override
  List<Object?> get props => <Object?>[journal];
}

class LifesumImportError extends LifesumImportState {
  const LifesumImportError(this.kind);

  final LifesumImportErrorKind kind;

  @override
  List<Object?> get props => <Object?>[kind];
}
