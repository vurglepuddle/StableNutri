import 'dart:convert';

DateTime cycleDate(DateTime date) => DateTime(date.year, date.month, date.day);
int cycleDays(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

class PeriodRecord {
  final String id;
  final DateTime start;
  final DateTime? end;

  /// Exclude the interval ending at this start when logging was incomplete.
  final bool gapBefore;

  const PeriodRecord({
    required this.id,
    required this.start,
    this.end,
    this.gapBefore = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'start': start.toIso8601String(),
    'end': end?.toIso8601String(),
    'gapBefore': gapBefore,
  };

  factory PeriodRecord.fromJson(Map<String, dynamic> json) => PeriodRecord(
    id: json['id'] as String,
    start: cycleDate(DateTime.parse(json['start'] as String)),
    end: json['end'] == null
        ? null
        : cycleDate(DateTime.parse(json['end'] as String)),
    gapBefore: json['gapBefore'] as bool? ?? false,
  );
}

class CycleData {
  final bool enabled;
  final int guessedCycleDays;
  final int guessedPeriodDays;
  final DateTime? guessedStart;
  final DateTime? expectedOverride;
  final bool reminderEnabled;
  final int reminderHour;
  final int reminderMinute;
  final List<PeriodRecord> records;

  const CycleData({
    this.enabled = false,
    this.guessedCycleDays = 28,
    this.guessedPeriodDays = 5,
    this.guessedStart,
    this.expectedOverride,
    this.reminderEnabled = false,
    this.reminderHour = 9,
    this.reminderMinute = 0,
    this.records = const [],
  });

  CycleData copyWith({
    bool? enabled,
    int? guessedCycleDays,
    int? guessedPeriodDays,
    DateTime? guessedStart,
    DateTime? expectedOverride,
    bool clearExpected = false,
    bool? reminderEnabled,
    int? reminderHour,
    int? reminderMinute,
    List<PeriodRecord>? records,
  }) => CycleData(
    enabled: enabled ?? this.enabled,
    guessedCycleDays: guessedCycleDays ?? this.guessedCycleDays,
    guessedPeriodDays: guessedPeriodDays ?? this.guessedPeriodDays,
    guessedStart: guessedStart ?? this.guessedStart,
    expectedOverride: clearExpected
        ? null
        : expectedOverride ?? this.expectedOverride,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    reminderHour: reminderHour ?? this.reminderHour,
    reminderMinute: reminderMinute ?? this.reminderMinute,
    records: List.unmodifiable(records ?? this.records),
  );

  List<PeriodRecord> get sorted =>
      [...records]..sort((a, b) => a.start.compareTo(b.start));
  List<int> get cycleLengths {
    final rows = sorted;
    return [
      for (var i = 1; i < rows.length; i++)
        if (!rows[i].gapBefore) cycleDays(rows[i - 1].start, rows[i].start),
    ];
  }

  List<int> get periodLengths => [
    for (final row in sorted)
      if (row.end != null) cycleDays(row.start, row.end!) + 1,
  ];
  double _average(List<int> values, int fallback) {
    final recent = values.reversed.take(6).toList();
    return recent.isEmpty
        ? fallback.toDouble()
        : recent.reduce((a, b) => a + b) / recent.length;
  }

  double get averageCycle => _average(cycleLengths, guessedCycleDays);
  double get averagePeriod => _average(periodLengths, guessedPeriodDays);
  DateTime? get expectedStart {
    if (expectedOverride != null) return expectedOverride;
    final start = sorted.isEmpty ? guessedStart : sorted.last.start;
    return start == null
        ? null
        : DateTime(start.year, start.month, start.day + averageCycle.round());
  }

  bool recordedOn(DateTime day, DateTime today) => records.any(
    (r) =>
        !cycleDate(day).isBefore(r.start) &&
        !cycleDate(day).isAfter(r.end ?? cycleDate(today)),
  );
  bool predictedOn(DateTime day) {
    final start = expectedStart;
    if (start == null) return false;
    final offset = cycleDays(start, day);
    return offset >= 0 && offset < averagePeriod.round();
  }

  void validate({DateTime? today}) {
    if (guessedCycleDays < 1 ||
        guessedCycleDays > 366 ||
        guessedPeriodDays < 1 ||
        guessedPeriodDays > guessedCycleDays ||
        reminderHour < 0 ||
        reminderHour > 23 ||
        reminderMinute < 0 ||
        reminderMinute > 59) {
      throw const FormatException('Invalid cycle settings');
    }
    final rows = sorted;
    final ids = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (r.id.isEmpty ||
          !ids.add(r.id) ||
          (r.end != null && r.end!.isBefore(r.start)) ||
          (today != null &&
              (r.start.isAfter(cycleDate(today)) ||
                  (r.end?.isAfter(cycleDate(today)) ?? false))) ||
          (i > 0 &&
              (rows[i - 1].end == null ||
                  !r.start.isAfter(rows[i - 1].end!)))) {
        throw const FormatException('Overlapping or invalid period dates');
      }
    }
  }

  String encode() => jsonEncode({
    'version': 1,
    'enabled': enabled,
    'guessedCycleDays': guessedCycleDays,
    'guessedPeriodDays': guessedPeriodDays,
    'guessedStart': guessedStart?.toIso8601String(),
    'expectedOverride': expectedOverride?.toIso8601String(),
    'reminderEnabled': reminderEnabled,
    'reminderHour': reminderHour,
    'reminderMinute': reminderMinute,
    'records': records.map((r) => r.toJson()).toList(),
  });

  factory CycleData.decode(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['version'] != 1) {
      throw const FormatException('Unsupported cycle version');
    }
    final data = CycleData(
      enabled: j['enabled'] as bool,
      guessedCycleDays: j['guessedCycleDays'] as int,
      guessedPeriodDays: j['guessedPeriodDays'] as int,
      guessedStart: j['guessedStart'] == null
          ? null
          : cycleDate(DateTime.parse(j['guessedStart'])),
      expectedOverride: j['expectedOverride'] == null
          ? null
          : cycleDate(DateTime.parse(j['expectedOverride'])),
      reminderEnabled: j['reminderEnabled'] as bool,
      reminderHour: j['reminderHour'] as int,
      reminderMinute: j['reminderMinute'] as int,
      records: List.unmodifiable(
        (j['records'] as List).map(
          (r) => PeriodRecord.fromJson(Map<String, dynamic>.from(r)),
        ),
      ),
    );
    data.validate();
    return data;
  }
}
