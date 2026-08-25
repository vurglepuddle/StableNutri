import 'package:equatable/equatable.dart';
import 'package:opennutritracker/core/data/dbo/body_measurement_log_dbo.dart';

enum BodyMeasurementType { waist, hips, chest, arm, thigh, bodyFat }

/// One optional body-measurement snapshot for a calendar day.
///
/// Lengths are stored in centimetres and body fat as a percentage. Weight is
/// deliberately kept in [WeightLogEntity], which remains the app's single
/// source of truth for current weight and weight history.
class BodyMeasurementLogEntity extends Equatable {
  final DateTime date;
  final double? waistCm;
  final double? hipsCm;
  final double? chestCm;
  final double? armCm;
  final double? thighCm;
  final double? bodyFatPercent;
  final String? note;

  const BodyMeasurementLogEntity({
    required this.date,
    this.waistCm,
    this.hipsCm,
    this.chestCm,
    this.armCm,
    this.thighCm,
    this.bodyFatPercent,
    this.note,
  });

  factory BodyMeasurementLogEntity.fromDBO(BodyMeasurementLogDBO dbo) {
    return BodyMeasurementLogEntity(
      date: dbo.date,
      waistCm: dbo.waistCm,
      hipsCm: dbo.hipsCm,
      chestCm: dbo.chestCm,
      armCm: dbo.armCm,
      thighCm: dbo.thighCm,
      bodyFatPercent: dbo.bodyFatPercent,
      note: dbo.note,
    );
  }

  bool get hasMeasurement =>
      waistCm != null ||
      hipsCm != null ||
      chestCm != null ||
      armCm != null ||
      thighCm != null ||
      bodyFatPercent != null;

  double? valueFor(BodyMeasurementType type) {
    return switch (type) {
      BodyMeasurementType.waist => waistCm,
      BodyMeasurementType.hips => hipsCm,
      BodyMeasurementType.chest => chestCm,
      BodyMeasurementType.arm => armCm,
      BodyMeasurementType.thigh => thighCm,
      BodyMeasurementType.bodyFat => bodyFatPercent,
    };
  }

  /// Rejects non-finite and implausible values before they reach storage.
  /// The broad limits avoid pretending to provide medical validation.
  bool get isValid {
    bool validLength(double? value) =>
        value == null || (value.isFinite && value > 0 && value <= 500);
    final fat = bodyFatPercent;
    return hasMeasurement &&
        validLength(waistCm) &&
        validLength(hipsCm) &&
        validLength(chestCm) &&
        validLength(armCm) &&
        validLength(thighCm) &&
        (fat == null || (fat.isFinite && fat > 0 && fat <= 100));
  }

  @override
  List<Object?> get props => [
    date,
    waistCm,
    hipsCm,
    chestCm,
    armCm,
    thighCm,
    bodyFatPercent,
    note,
  ];
}
