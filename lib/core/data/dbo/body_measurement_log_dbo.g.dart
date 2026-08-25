// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'body_measurement_log_dbo.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BodyMeasurementLogDBOAdapter extends TypeAdapter<BodyMeasurementLogDBO> {
  @override
  final typeId = 23;

  @override
  BodyMeasurementLogDBO read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BodyMeasurementLogDBO(
      date: fields[0] as DateTime,
      waistCm: (fields[1] as num?)?.toDouble(),
      hipsCm: (fields[2] as num?)?.toDouble(),
      chestCm: (fields[3] as num?)?.toDouble(),
      armCm: (fields[4] as num?)?.toDouble(),
      thighCm: (fields[5] as num?)?.toDouble(),
      bodyFatPercent: (fields[6] as num?)?.toDouble(),
      note: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, BodyMeasurementLogDBO obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.waistCm)
      ..writeByte(2)
      ..write(obj.hipsCm)
      ..writeByte(3)
      ..write(obj.chestCm)
      ..writeByte(4)
      ..write(obj.armCm)
      ..writeByte(5)
      ..write(obj.thighCm)
      ..writeByte(6)
      ..write(obj.bodyFatPercent)
      ..writeByte(7)
      ..write(obj.note);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BodyMeasurementLogDBOAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BodyMeasurementLogDBO _$BodyMeasurementLogDBOFromJson(
  Map<String, dynamic> json,
) => BodyMeasurementLogDBO(
  date: DateTime.parse(json['date'] as String),
  waistCm: (json['waistCm'] as num?)?.toDouble(),
  hipsCm: (json['hipsCm'] as num?)?.toDouble(),
  chestCm: (json['chestCm'] as num?)?.toDouble(),
  armCm: (json['armCm'] as num?)?.toDouble(),
  thighCm: (json['thighCm'] as num?)?.toDouble(),
  bodyFatPercent: (json['bodyFatPercent'] as num?)?.toDouble(),
  note: json['note'] as String?,
);

Map<String, dynamic> _$BodyMeasurementLogDBOToJson(
  BodyMeasurementLogDBO instance,
) => <String, dynamic>{
  'date': instance.date.toIso8601String(),
  'waistCm': instance.waistCm,
  'hipsCm': instance.hipsCm,
  'chestCm': instance.chestCm,
  'armCm': instance.armCm,
  'thighCm': instance.thighCm,
  'bodyFatPercent': instance.bodyFatPercent,
  'note': instance.note,
};
