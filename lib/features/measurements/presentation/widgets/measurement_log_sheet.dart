import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_body_measurement_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_weight_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_body_measurement_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_weight_log_usecase.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/measurements/presentation/utils/body_measurement_format.dart';
import 'package:opennutritracker/features/profile/presentation/widgets/body_weight_input.dart';
import 'package:opennutritracker/generated/l10n.dart';

Future<bool> showMeasurementLogSheet(
  BuildContext context, {
  required double currentWeightKg,
  required BodyWeightUnit bodyWeightUnit,
  required bool usesImperialLengthUnits,
  AddWeightLogUsecase? addWeightUsecase,
  GetWeightLogUsecase? getWeightUsecase,
  AddBodyMeasurementLogUsecase? addMeasurementUsecase,
  GetBodyMeasurementLogUsecase? getMeasurementUsecase,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => MeasurementLogSheet(
      currentWeightKg: currentWeightKg,
      bodyWeightUnit: bodyWeightUnit,
      usesImperialLengthUnits: usesImperialLengthUnits,
      addWeightUsecase: addWeightUsecase,
      getWeightUsecase: getWeightUsecase,
      addMeasurementUsecase: addMeasurementUsecase,
      getMeasurementUsecase: getMeasurementUsecase,
    ),
  );
  return result ?? false;
}

class MeasurementLogSheet extends StatefulWidget {
  final double currentWeightKg;
  final BodyWeightUnit bodyWeightUnit;
  final bool usesImperialLengthUnits;
  final AddWeightLogUsecase? addWeightUsecase;
  final GetWeightLogUsecase? getWeightUsecase;
  final AddBodyMeasurementLogUsecase? addMeasurementUsecase;
  final GetBodyMeasurementLogUsecase? getMeasurementUsecase;

  const MeasurementLogSheet({
    super.key,
    required this.currentWeightKg,
    required this.bodyWeightUnit,
    required this.usesImperialLengthUnits,
    this.addWeightUsecase,
    this.getWeightUsecase,
    this.addMeasurementUsecase,
    this.getMeasurementUsecase,
  });

  @override
  State<MeasurementLogSheet> createState() => _MeasurementLogSheetState();
}

class _MeasurementLogSheetState extends State<MeasurementLogSheet> {
  late final AddWeightLogUsecase _addWeight =
      widget.addWeightUsecase ?? locator<AddWeightLogUsecase>();
  late final GetWeightLogUsecase _getWeight =
      widget.getWeightUsecase ?? locator<GetWeightLogUsecase>();
  late final AddBodyMeasurementLogUsecase _addMeasurement =
      widget.addMeasurementUsecase ?? locator<AddBodyMeasurementLogUsecase>();
  late final GetBodyMeasurementLogUsecase _getMeasurement =
      widget.getMeasurementUsecase ?? locator<GetBodyMeasurementLogUsecase>();

  final _controllers = <BodyMeasurementType, TextEditingController>{
    for (final type in BodyMeasurementType.values)
      type: TextEditingController(),
  };
  final _noteController = TextEditingController();
  late DateTime _date;
  double? _weightKg;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    _loadDate(useCurrentWeightFallback: true);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadDate({bool useCurrentWeightFallback = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await Future.wait<Object?>([
      _getWeight.getEntry(_date),
      _getMeasurement.getEntry(_date),
    ]);
    if (!mounted) return;
    final weight = results[0] as WeightLogEntity?;
    final measurement = results[1] as BodyMeasurementLogEntity?;
    _weightKg =
        weight?.weightKg ??
        (useCurrentWeightFallback ? widget.currentWeightKg : null);
    for (final type in BodyMeasurementType.values) {
      final value = measurement?.valueFor(type);
      final display = value == null
          ? null
          : type == BodyMeasurementType.bodyFat
          ? value
          : bodyMeasurementToDisplay(value, widget.usesImperialLengthUnits);
      _controllers[type]!.text = display == null ? '' : _trim(display);
    }
    _noteController.text = measurement?.note ?? weight?.note ?? '';
    setState(() => _loading = false);
  }

  String _trim(double value) {
    final rounded = double.parse(value.toStringAsFixed(1));
    return rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked == null || picked == _date) return;
    _date = DateTime(picked.year, picked.month, picked.day);
    await _loadDate();
  }

  double? _parse(BodyMeasurementType type) {
    final raw = _controllers[type]!.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null) return double.nan;
    return type == BodyMeasurementType.bodyFat
        ? value
        : bodyMeasurementFromDisplay(value, widget.usesImperialLengthUnits);
  }

  Future<void> _save() async {
    final measurement = BodyMeasurementLogEntity(
      date: _date,
      waistCm: _parse(BodyMeasurementType.waist),
      hipsCm: _parse(BodyMeasurementType.hips),
      chestCm: _parse(BodyMeasurementType.chest),
      armCm: _parse(BodyMeasurementType.arm),
      thighCm: _parse(BodyMeasurementType.thigh),
      bodyFatPercent: _parse(BodyMeasurementType.bodyFat),
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
    );
    if (_weightKg == null && !measurement.hasMeasurement) {
      setState(() => _error = S.of(context).measurementsNothingToSave);
      return;
    }
    if (measurement.hasMeasurement && !measurement.isValid) {
      setState(() => _error = S.of(context).measurementsInvalidValue);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final note = measurement.note;
    if (_weightKg != null) {
      await _addWeight.addEntry(
        WeightLogEntity(date: _date, weightKg: _weightKg!, note: note),
      );
    }
    if (measurement.hasMeasurement) {
      await _addMeasurement.addEntry(measurement);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  String _label(BuildContext context, BodyMeasurementType type) {
    return switch (type) {
      BodyMeasurementType.waist => S.of(context).measurementsWaist,
      BodyMeasurementType.hips => S.of(context).measurementsHips,
      BodyMeasurementType.chest => S.of(context).measurementsChest,
      BodyMeasurementType.arm => S.of(context).measurementsArm,
      BodyMeasurementType.thigh => S.of(context).measurementsThigh,
      BodyMeasurementType.bodyFat => S.of(context).measurementsBodyFat,
    };
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    return AnimatedPadding(
      duration: AppMotion.durationShort,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Dimens.spacing20,
                  0,
                  Dimens.spacing20,
                  Dimens.spacing24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact =
                            constraints.maxWidth < 340 ||
                            MediaQuery.textScalerOf(context).scale(1) >= 1.4;
                        final localizations = MaterialLocalizations.of(context);
                        final dateChip = Semantics(
                          identifier: 'measurements-date-picker',
                          label: localizations.formatMediumDate(_date),
                          child: ActionChip(
                            avatar: const Icon(
                              Icons.calendar_today_rounded,
                              size: 16,
                            ),
                            label: Text(
                              compact
                                  ? localizations.formatShortDate(_date)
                                  : localizations.formatMediumDate(_date),
                            ),
                            onPressed: _saving ? null : _pickDate,
                          ),
                        );
                        final title = Text(
                          S.of(context).measurementsLogTitle,
                          style: Theme.of(context).textTheme.titleLarge,
                        );
                        if (compact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              const SizedBox(height: Dimens.spacing8),
                              dateChip,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: title),
                            dateChip,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: Dimens.spacing16),
                    Container(
                      padding: const EdgeInsets.all(Dimens.spacing16),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.42),
                        borderRadius: Dimens.borderRadiusM,
                        border: Border.all(color: palette.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.monitor_weight_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: Dimens.spacing8),
                              Text(
                                S.of(context).weightHistoryWeightLabel,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: Dimens.spacing8),
                          BodyWeightInput(
                            key: ValueKey(
                              'measurement-weight-${_date.toIso8601String()}',
                            ),
                            initialKg: _weightKg,
                            unit: widget.bodyWeightUnit,
                            identifierPrefix: 'measurements',
                            onChangedKg: (value) => _weightKg = value,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Dimens.spacing16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final twoColumns =
                            constraints.maxWidth >= 340 &&
                            MediaQuery.textScalerOf(context).scale(1) < 1.5;
                        final width = twoColumns
                            ? (constraints.maxWidth - Dimens.spacing12) / 2
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: Dimens.spacing12,
                          runSpacing: Dimens.spacing12,
                          children: [
                            for (final type in BodyMeasurementType.values)
                              SizedBox(
                                width: width,
                                child: Semantics(
                                  identifier: 'measurements-${type.name}-input',
                                  child: TextField(
                                    key: Key('measurement-${type.name}-input'),
                                    controller: _controllers[type],
                                    enabled: !_saving,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d+([.,]\d{0,1})?$'),
                                      ),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: _label(context, type),
                                      suffixText:
                                          type == BodyMeasurementType.bodyFat
                                          ? '%'
                                          : widget.usesImperialLengthUnits
                                          ? S.of(context).inLabel
                                          : S.of(context).cmLabel,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: Dimens.spacing12),
                    TextField(
                      key: const Key('measurement-note-input'),
                      controller: _noteController,
                      enabled: !_saving,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 240,
                      decoration: InputDecoration(
                        labelText: S.of(context).measurementsNoteLabel,
                        hintText: S.of(context).measurementsNoteHint,
                        prefixIcon: const Icon(Icons.notes_rounded),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Dimens.spacing4),
                      Text(
                        _error!,
                        key: const Key('measurementFormError'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: Dimens.spacing8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cancel = OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: Text(S.of(context).dialogCancelLabel),
                        );
                        final save = FilledButton.icon(
                          key: const Key('measurement-save-button'),
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(S.of(context).measurementsSave),
                        );
                        final stackActions =
                            constraints.maxWidth < 340 ||
                            MediaQuery.textScalerOf(context).scale(1) >= 1.4;
                        if (stackActions) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              save,
                              const SizedBox(height: Dimens.spacing8),
                              cancel,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: cancel),
                            const SizedBox(width: Dimens.spacing12),
                            Expanded(flex: 2, child: save),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
