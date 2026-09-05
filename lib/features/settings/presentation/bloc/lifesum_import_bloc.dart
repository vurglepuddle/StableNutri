import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_coordinator.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_journal.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_manifest.dart';

part 'lifesum_import_event.dart';
part 'lifesum_import_state.dart';

class LifesumImportBloc extends Bloc<LifesumImportEvent, LifesumImportState> {
  LifesumImportBloc(this._coordinator) : super(const LifesumImportInitial()) {
    on<ChooseLifesumArchiveEvent>(_onChooseArchive);
    on<SetLifesumImportCategoryEvent>(_onSetCategory);
    on<ConfirmLifesumImportEvent>(_onConfirm);
    on<ResetLifesumImportEvent>((event, emit) async {
      if (state is LifesumImportApplying || state is LifesumImportLoading) {
        return;
      }
      await _coordinator.discardArchive();
      emit(const LifesumImportInitial());
    });
  }

  final LifesumImportCoordinator _coordinator;

  @override
  Future<void> close() async {
    await super.close();
    await _coordinator.discardArchive();
  }

  Future<void> _onChooseArchive(
    ChooseLifesumArchiveEvent event,
    Emitter<LifesumImportState> emit,
  ) async {
    if (state is LifesumImportApplying || state is LifesumImportLoading) return;
    emit(const LifesumImportLoading());
    try {
      final preparation = await _coordinator.chooseArchive();
      if (emit.isDone) {
        await _coordinator.discardArchive();
        return;
      }
      if (preparation == null) {
        emit(const LifesumImportInitial());
        return;
      }
      emit(
        LifesumImportReady(
          preparation: preparation,
          selection: const LifesumImportSelection(),
        ),
      );
    } on Object catch (error) {
      if (emit.isDone) return;
      emit(
        LifesumImportError(
          _classifyError(
            error,
            fallback: LifesumImportErrorKind.invalidArchive,
          ),
        ),
      );
    }
  }

  void _onSetCategory(
    SetLifesumImportCategoryEvent event,
    Emitter<LifesumImportState> emit,
  ) {
    final current = state;
    if (current is! LifesumImportReady) return;
    final selection = switch (event.category) {
      LifesumImportCategory.food => current.selection.copyWith(
        includeFood: event.included,
      ),
      LifesumImportCategory.activity => current.selection.copyWith(
        includeActivity: event.included,
      ),
      LifesumImportCategory.weight => current.selection.copyWith(
        includeWeights: event.included,
      ),
      LifesumImportCategory.bodyMeasurements => current.selection.copyWith(
        includeBodyMeasurements: event.included,
      ),
      LifesumImportCategory.estimatedWater => current.selection.copyWith(
        includeEstimatedWater: event.included,
      ),
    };
    emit(
      LifesumImportReady(
        preparation: current.preparation,
        selection: selection,
      ),
    );
  }

  Future<void> _onConfirm(
    ConfirmLifesumImportEvent event,
    Emitter<LifesumImportState> emit,
  ) async {
    final current = state;
    if (current is! LifesumImportReady) return;
    emit(
      LifesumImportApplying(
        preparation: current.preparation,
        selection: current.selection,
      ),
    );
    try {
      final journal = await _coordinator.confirm(
        current.preparation,
        selection: current.selection,
      );
      if (journal.phase == LifesumImportJournalPhase.completed) {
        emit(LifesumImportSuccess(journal));
      } else {
        emit(const LifesumImportError(LifesumImportErrorKind.rolledBack));
      }
    } on Object catch (error) {
      emit(
        LifesumImportError(
          _classifyError(error, fallback: LifesumImportErrorKind.importFailed),
        ),
      );
    }
  }

  static LifesumImportErrorKind _classifyError(
    Object error, {
    required LifesumImportErrorKind fallback,
  }) {
    if (error is LifesumImportCoordinatorException) {
      return switch (error.failure) {
        LifesumImportCoordinatorFailure.invalidArchiveSelection =>
          LifesumImportErrorKind.invalidArchive,
        LifesumImportCoordinatorFailure.activeProfileChanged =>
          LifesumImportErrorKind.profileChanged,
        LifesumImportCoordinatorFailure.previewChanged =>
          LifesumImportErrorKind.previewChanged,
        LifesumImportCoordinatorFailure.alreadyConfirmed ||
        LifesumImportCoordinatorFailure.foreignPreparation =>
          LifesumImportErrorKind.confirmationExpired,
      };
    }
    return fallback;
  }
}
