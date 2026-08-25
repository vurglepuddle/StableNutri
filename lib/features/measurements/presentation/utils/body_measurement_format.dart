import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';

double bodyMeasurementToDisplay(double cm, bool imperial) =>
    imperial ? UnitCalc.cmToInches(cm) : cm;

double bodyMeasurementFromDisplay(double value, bool imperial) =>
    imperial ? UnitCalc.inchesToCm(value) : value;

String formatBodyMeasurementValue(
  double value,
  BodyMeasurementType type, {
  required bool imperial,
  required String cmLabel,
  required String inLabel,
}) {
  if (type == BodyMeasurementType.bodyFat) {
    return '${_format(value)}%';
  }
  final display = bodyMeasurementToDisplay(value, imperial);
  return '${_format(display)} ${imperial ? inLabel : cmLabel}';
}

String _format(double value) {
  final rounded = double.parse(value.toStringAsFixed(1));
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}
