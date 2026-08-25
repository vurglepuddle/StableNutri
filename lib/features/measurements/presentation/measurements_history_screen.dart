import 'package:flutter/material.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/usecase/delete_body_measurement_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_body_measurement_log_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/delete_dialog.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/measurements/presentation/utils/body_measurement_format.dart';
import 'package:opennutritracker/features/measurements/presentation/widgets/measurement_log_sheet.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

class MeasurementsHistoryScreen extends StatefulWidget {
  const MeasurementsHistoryScreen({super.key});

  @override
  State<MeasurementsHistoryScreen> createState() =>
      _MeasurementsHistoryScreenState();
}

class _MeasurementsHistoryScreenState extends State<MeasurementsHistoryScreen> {
  bool _loading = true;
  List<BodyMeasurementLogEntity> _entries = const [];
  double _currentWeightKg = 70;
  BodyWeightUnit _bodyWeightUnit = BodyWeightUnit.kg;
  bool _usesImperialLengthUnits = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<Object>([
      locator<GetBodyMeasurementLogUsecase>().getAllEntries(),
      locator<ConfigRepository>().getConfig(),
      locator<GetUserUsecase>().getUserData(),
    ]);
    if (!mounted) return;
    final entries = values[0] as List<BodyMeasurementLogEntity>;
    final config = values[1] as ConfigEntity;
    final user = values[2] as UserEntity;
    entries.sort((a, b) => b.date.compareTo(a.date));
    setState(() {
      _entries = entries;
      _bodyWeightUnit = config.bodyWeightUnit;
      _usesImperialLengthUnits = config.usesImperialHeightUnits;
      _currentWeightKg = user.weightKG;
      _loading = false;
    });
  }

  String _label(BodyMeasurementType type) {
    return switch (type) {
      BodyMeasurementType.waist => S.of(context).measurementsWaist,
      BodyMeasurementType.hips => S.of(context).measurementsHips,
      BodyMeasurementType.chest => S.of(context).measurementsChest,
      BodyMeasurementType.arm => S.of(context).measurementsArm,
      BodyMeasurementType.thigh => S.of(context).measurementsThigh,
      BodyMeasurementType.bodyFat => S.of(context).measurementsBodyFat,
    };
  }

  Future<void> _add() async {
    final saved = await showMeasurementLogSheet(
      context,
      currentWeightKg: _currentWeightKg,
      bodyWeightUnit: _bodyWeightUnit,
      usesImperialLengthUnits: _usesImperialLengthUnits,
    );
    if (!saved || !mounted) return;
    final user = await locator<GetUserUsecase>().getUserData();
    await locator<ProfileBloc>().updateUser(user);
    await _load();
  }

  Future<void> _delete(BodyMeasurementLogEntity entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const DeleteDialog(),
    );
    if (confirmed != true) return;
    await locator<DeleteBodyMeasurementLogUsecase>().deleteEntry(entry.date);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).measurementsHistoryTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: Text(S.of(context).measurementsLogTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(Dimens.spacing24),
                child: Text(
                  S.of(context).measurementsHistoryEmpty,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: _entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final entry = _entries[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Dimens.spacing16,
                    vertical: Dimens.spacing8,
                  ),
                  title: Text(
                    MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(entry.date),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: Dimens.spacing8),
                      Wrap(
                        spacing: Dimens.spacing8,
                        runSpacing: Dimens.spacing4,
                        children: [
                          for (final type in BodyMeasurementType.values)
                            if (entry.valueFor(type) != null)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  '${_label(type)} ${formatBodyMeasurementValue(entry.valueFor(type)!, type, imperial: _usesImperialLengthUnits, cmLabel: S.of(context).cmLabel, inLabel: S.of(context).inLabel)}',
                                ),
                              ),
                        ],
                      ),
                      if (entry.note?.isNotEmpty == true) ...[
                        const SizedBox(height: Dimens.spacing4),
                        Text(entry.note!),
                      ],
                    ],
                  ),
                  trailing: IconButton(
                    tooltip: S.of(context).measurementsDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _delete(entry),
                  ),
                );
              },
            ),
    );
  }
}
