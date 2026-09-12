import 'package:equatable/equatable.dart';

/// One Health Connect aggregate for a logical diary day. Counts are absolute
/// snapshots; refreshing a day replaces its count, never adds to it.
class DailySteps extends Equatable {
  final DateTime day;
  final int steps;
  final DateTime readAt;
  final int offsetMinutes;

  const DailySteps({
    required this.day,
    required this.steps,
    required this.readAt,
    required this.offsetMinutes,
  });

  String get dayKey =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  bool get isValid =>
      steps >= 0 &&
      offsetMinutes >= 0 &&
      offsetMinutes < 1440 &&
      day.hour == 0 &&
      day.minute == 0 &&
      day.second == 0 &&
      day.millisecond == 0 &&
      day.microsecond == 0 &&
      day.year >= 1970 &&
      day.year <= 9999;

  factory DailySteps.fromJson(Map<String, dynamic> json) {
    final dayText = json['day'] as String;
    final day = DateTime.parse(dayText);
    final row = DailySteps(
      day: day,
      steps: json['steps'] as int,
      readAt: DateTime.fromMillisecondsSinceEpoch(json['readAtMs'] as int),
      offsetMinutes: json['offsetMinutes'] as int,
    );
    if (!row.isValid || dayText != row.dayKey) {
      throw const FormatException('Invalid daily steps');
    }
    return row;
  }

  Map<String, dynamic> toJson() => {
    'day': dayKey,
    'steps': steps,
    'readAtMs': readAt.millisecondsSinceEpoch,
    'offsetMinutes': offsetMinutes,
  };

  @override
  List<Object?> get props => [dayKey, steps, readAt, offsetMinutes];
}
