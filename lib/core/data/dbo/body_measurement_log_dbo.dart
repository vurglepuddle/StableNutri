import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';

part 'body_measurement_log_dbo.g.dart';

@HiveType(typeId: 23)
@JsonSerializable()
class BodyMeasurementLogDBO extends HiveObject {
  @HiveField(0)
  DateTime date;
  @HiveField(1)
  double? waistCm;
  @HiveField(2)
  double? hipsCm;
  @HiveField(3)
  double? chestCm;
  @HiveField(4)
  double? armCm;
  @HiveField(5)
  double? thighCm;
  @HiveField(6)
  double? bodyFatPercent;
  @HiveField(7)
  String? note;

  BodyMeasurementLogDBO({
    required this.date,
    this.waistCm,
    this.hipsCm,
    this.chestCm,
    this.armCm,
    this.thighCm,
    this.bodyFatPercent,
    this.note,
  });

  factory BodyMeasurementLogDBO.fromEntity(BodyMeasurementLogEntity entity) {
    return BodyMeasurementLogDBO(
      date: entity.date,
      waistCm: entity.waistCm,
      hipsCm: entity.hipsCm,
      chestCm: entity.chestCm,
      armCm: entity.armCm,
      thighCm: entity.thighCm,
      bodyFatPercent: entity.bodyFatPercent,
      note: entity.note,
    );
  }

  factory BodyMeasurementLogDBO.fromJson(Map<String, dynamic> json) =>
      _$BodyMeasurementLogDBOFromJson(json);

  Map<String, dynamic> toJson() => _$BodyMeasurementLogDBOToJson(this);
}
