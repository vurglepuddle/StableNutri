import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/utils/csv_row_parser.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';

enum LifesumActivityIssueCode {
  emptyFile,
  missingRequiredColumns,
  duplicateHeaderColumns,
  malformedRow,
  missingRequiredValue,
  invalidDate,
  invalidNumber,
  negativeDuration,
  nonPositiveCalories,
  unsupportedSource,
  healthConnectMirrorIgnored,
  unexpectedHealthConnectCalories,
}

/// Value-free feedback for activity rows. Source titles and health values are
/// deliberately never retained in an issue.
class LifesumActivityIssue {
  const LifesumActivityIssue({required this.code, this.rowNumber, this.column});

  final LifesumActivityIssueCode code;
  final int? rowNumber;
  final String? column;

  bool get blocksSection =>
      code == LifesumActivityIssueCode.emptyFile ||
      code == LifesumActivityIssueCode.missingRequiredColumns ||
      code == LifesumActivityIssueCode.duplicateHeaderColumns;
}

class LifesumActivityCandidate {
  const LifesumActivityCandidate({
    required this.activity,
    required this.sourceRowNumber,
  });

  final UserActivityEntity activity;
  final int sourceRowNumber;
}

/// Aggregate burned energy needed by the later tracked-day apply policy.
class LifesumActivityDayCandidate {
  const LifesumActivityDayCandidate({
    required this.day,
    required this.activityCount,
    required this.durationMinutes,
    required this.caloriesBurned,
  });

  final DateTime day;
  final int activityCount;
  final double durationMinutes;
  final double caloriesBurned;
}

class LifesumActivityParseResult {
  LifesumActivityParseResult({
    required this.sourceRowCount,
    required List<LifesumActivityCandidate> candidates,
    required List<LifesumActivityDayCandidate> trackedDays,
    required List<LifesumActivityIssue> issues,
  }) : candidates = List<LifesumActivityCandidate>.unmodifiable(candidates),
       trackedDays = List<LifesumActivityDayCandidate>.unmodifiable(
         trackedDays,
       ),
       issues = List<LifesumActivityIssue>.unmodifiable(issues);

  final int sourceRowCount;
  final List<LifesumActivityCandidate> candidates;
  final List<LifesumActivityDayCandidate> trackedDays;
  final List<LifesumActivityIssue> issues;

  List<UserActivityEntity> get activities =>
      List<UserActivityEntity>.unmodifiable(
        candidates.map((candidate) => candidate.activity),
      );

  int get ignoredHealthConnectCount => issues
      .where(
        (issue) =>
            issue.code == LifesumActivityIssueCode.healthConnectMirrorIgnored,
      )
      .length;

  int get blockingIssueCount =>
      issues.where((issue) => issue.blocksSection).length;

  int get warningCount => issues.where((issue) => !issue.blocksSection).length;
}

/// Converts the user-confirmed Lifesum activity source into Stable custom
/// activities. Health Connect rows are step-derived mirrors and are reported
/// but never converted into candidates.
class LifesumActivityParser {
  static LifesumActivityParseResult parse(
    String csv, {
    int dayStartOffsetMinutes = 0,
  }) {
    final issues = <LifesumActivityIssue>[];
    final table = _ActivityCsvTable.parse(csv, issues);
    final candidates = <LifesumActivityCandidate>[];
    final trackedDayBuilders = <int, _ActivityDayBuilder>{};
    final occurrenceCounts = <String, int>{};
    final offsetMinutes = _validOffset(dayStartOffsetMinutes);

    for (final row in table.rows) {
      final date = _parseDate(row['date']);
      if (date == null) {
        issues.add(
          LifesumActivityIssue(
            code: LifesumActivityIssueCode.invalidDate,
            rowNumber: row.rowNumber,
            column: 'date',
          ),
        );
        continue;
      }

      final source = _normalizeSource(row['source']);
      if (source != 'lifesum' && source != 'healthconnect') {
        issues.add(
          LifesumActivityIssue(
            code: LifesumActivityIssueCode.unsupportedSource,
            rowNumber: row.rowNumber,
            column: 'source',
          ),
        );
        continue;
      }

      final calories = _parseFiniteDouble(row['calories_burned']);
      if (calories == null) {
        issues.add(
          LifesumActivityIssue(
            code: LifesumActivityIssueCode.invalidNumber,
            rowNumber: row.rowNumber,
            column: 'calories_burned',
          ),
        );
        continue;
      }
      if (source == 'healthconnect') {
        // The source policy ignores these step-derived mirrors wholesale. In
        // particular, their duration field is not Lifesum's numeric-minute
        // representation and must not be parsed as if it were.
        issues.add(
          LifesumActivityIssue(
            code: calories == 0
                ? LifesumActivityIssueCode.healthConnectMirrorIgnored
                : LifesumActivityIssueCode.unexpectedHealthConnectCalories,
            rowNumber: row.rowNumber,
            column: 'source',
          ),
        );
        continue;
      }
      if (calories <= 0) {
        issues.add(
          LifesumActivityIssue(
            code: LifesumActivityIssueCode.nonPositiveCalories,
            rowNumber: row.rowNumber,
            column: 'calories_burned',
          ),
        );
        continue;
      }

      final title = row['title']?.trim() ?? '';
      if (title.isEmpty) {
        issues.add(
          LifesumActivityIssue(
            code: LifesumActivityIssueCode.missingRequiredValue,
            rowNumber: row.rowNumber,
            column: 'title',
          ),
        );
        continue;
      }

      final duration = _parseFiniteDouble(row['duration_min']);
      if (duration == null) {
        issues.add(
          LifesumActivityIssue(
            code: LifesumActivityIssueCode.invalidNumber,
            rowNumber: row.rowNumber,
            column: 'duration_min',
          ),
        );
        continue;
      }
      if (duration < 0) {
        issues.add(
          LifesumActivityIssue(
            code: LifesumActivityIssueCode.negativeDuration,
            rowNumber: row.rowNumber,
            column: 'duration_min',
          ),
        );
        continue;
      }

      final canonicalRow = LifesumExportSection.exercise.requiredColumns
          .map((column) => row[column]?.trim() ?? '')
          .join('\u001f');
      final occurrence = occurrenceCounts.update(
        canonicalRow,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      final activity = UserActivityEntity(
        'lifesum-activity-${_stableDigest(canonicalRow)}-'
        '${occurrence.toString().padLeft(3, '0')}',
        duration,
        calories,
        DateTime(date.year, date.month, date.day).add(
          Duration(
            minutes: offsetMinutes + 12 * 60,
            microseconds: row.rowNumber,
          ),
        ),
        PhysicalActivityEntity.customNamed(title),
        userKcal: calories,
      );
      candidates.add(
        LifesumActivityCandidate(
          activity: activity,
          sourceRowNumber: row.rowNumber,
        ),
      );
      trackedDayBuilders
          .putIfAbsent(_dayKey(date), () => _ActivityDayBuilder(date))
          .add(duration: duration, calories: calories);
    }

    final trackedDays =
        trackedDayBuilders.values.map((builder) => builder.build()).toList()
          ..sort((left, right) => left.day.compareTo(right.day));
    return LifesumActivityParseResult(
      sourceRowCount: table.sourceRowCount,
      candidates: candidates,
      trackedDays: trackedDays,
      issues: issues,
    );
  }

  static int _validOffset(int value) =>
      value >= 0 && value < 24 * 60 ? value : 0;

  static double? _parseFiniteDouble(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = double.tryParse(raw.trim());
    return value != null && value.isFinite ? value : null;
  }

  static String _normalizeSource(String? raw) =>
      (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (year < 1900 || year > 2200) return null;
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static int _dayKey(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  static String _stableDigest(String input) {
    var fnv = 0x811c9dc5;
    var djb = 5381;
    for (final unit in input.codeUnits) {
      fnv ^= unit;
      fnv = (fnv * 0x01000193) & 0xffffffff;
      djb = (((djb << 5) + djb) ^ unit) & 0xffffffff;
    }
    return '${fnv.toRadixString(16).padLeft(8, '0')}'
        '${djb.toRadixString(16).padLeft(8, '0')}';
  }
}

class _ActivityCsvTable {
  const _ActivityCsvTable({required this.rows, required this.sourceRowCount});

  final List<_ActivityCsvRow> rows;
  final int sourceRowCount;

  static _ActivityCsvTable parse(
    String csv,
    List<LifesumActivityIssue> issues,
  ) {
    final lines = csv.split(RegExp(r'\r\n?|\n'));
    var headerIndex = -1;
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].trim().isNotEmpty) {
        headerIndex = index;
        break;
      }
    }
    if (headerIndex == -1) {
      issues.add(
        const LifesumActivityIssue(code: LifesumActivityIssueCode.emptyFile),
      );
      return const _ActivityCsvTable(
        rows: <_ActivityCsvRow>[],
        sourceRowCount: 0,
      );
    }

    final headers = CsvRowParser.splitRow(
      lines[headerIndex],
    ).map((value) => value.trim().toLowerCase()).toList();
    if (headers.isNotEmpty) {
      headers[0] = headers[0].replaceFirst('\ufeff', '');
    }
    final dataLines = <({int rowNumber, String value})>[];
    for (var index = headerIndex + 1; index < lines.length; index++) {
      if (lines[index].trim().isNotEmpty) {
        dataLines.add((rowNumber: index + 1, value: lines[index]));
      }
    }

    if (headers.toSet().length != headers.length) {
      issues.add(
        const LifesumActivityIssue(
          code: LifesumActivityIssueCode.duplicateHeaderColumns,
        ),
      );
      return _ActivityCsvTable(
        rows: const <_ActivityCsvRow>[],
        sourceRowCount: dataLines.length,
      );
    }
    final headerSet = headers.toSet();
    final missing = LifesumExportSection.exercise.requiredColumns.where(
      (column) => !headerSet.contains(column),
    );
    if (missing.isNotEmpty) {
      for (final column in missing) {
        issues.add(
          LifesumActivityIssue(
            code: LifesumActivityIssueCode.missingRequiredColumns,
            column: column,
          ),
        );
      }
      return _ActivityCsvTable(
        rows: const <_ActivityCsvRow>[],
        sourceRowCount: dataLines.length,
      );
    }

    final rows = <_ActivityCsvRow>[];
    for (final dataLine in dataLines) {
      final values = CsvRowParser.splitRow(dataLine.value);
      if (values.length != headers.length) {
        issues.add(
          LifesumActivityIssue(
            code: LifesumActivityIssueCode.malformedRow,
            rowNumber: dataLine.rowNumber,
          ),
        );
        continue;
      }
      rows.add(
        _ActivityCsvRow(
          rowNumber: dataLine.rowNumber,
          values: <String, String>{
            for (var index = 0; index < headers.length; index++)
              headers[index]: values[index],
          },
        ),
      );
    }
    return _ActivityCsvTable(rows: rows, sourceRowCount: dataLines.length);
  }
}

class _ActivityCsvRow {
  const _ActivityCsvRow({required this.rowNumber, required this.values});

  final int rowNumber;
  final Map<String, String> values;

  String? operator [](String column) => values[column];
}

class _ActivityDayBuilder {
  _ActivityDayBuilder(this.day);

  final DateTime day;
  var activityCount = 0;
  var durationMinutes = 0.0;
  var caloriesBurned = 0.0;

  void add({required double duration, required double calories}) {
    activityCount++;
    durationMinutes += duration;
    caloriesBurned += calories;
  }

  LifesumActivityDayCandidate build() => LifesumActivityDayCandidate(
    day: day,
    activityCount: activityCount,
    durationMinutes: durationMinutes,
    caloriesBurned: caloriesBurned,
  );
}
