import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/utils/bounds/ranges_const.dart';
import 'package:opennutritracker/core/utils/csv_row_parser.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';

enum LifesumMeasurementIssueCode {
  emptyFile,
  missingRequiredColumns,
  duplicateHeaderColumns,
  malformedRow,
  invalidDate,
  invalidNumber,
  outOfRange,
  unsupportedMeasurement,
  unsupportedUnit,
  duplicateSameDayValue,
  conflictingSameDayValue,
}

/// Structural parse feedback that never includes the source cell value.
class LifesumMeasurementIssue {
  const LifesumMeasurementIssue({
    required this.section,
    required this.code,
    this.rowNumber,
    this.column,
  });

  final LifesumExportSection section;
  final LifesumMeasurementIssueCode code;
  final int? rowNumber;
  final String? column;

  bool get blocksSection =>
      code == LifesumMeasurementIssueCode.emptyFile ||
      code == LifesumMeasurementIssueCode.missingRequiredColumns ||
      code == LifesumMeasurementIssueCode.duplicateHeaderColumns;
}

class LifesumMeasurementParseResult {
  LifesumMeasurementParseResult({
    required List<WeightLogEntity> weights,
    required List<BodyMeasurementLogEntity> bodyMeasurements,
    required List<LifesumMeasurementIssue> issues,
    required Map<LifesumExportSection, int> sourceRowCounts,
  }) : weights = List<WeightLogEntity>.unmodifiable(weights),
       bodyMeasurements = List<BodyMeasurementLogEntity>.unmodifiable(
         bodyMeasurements,
       ),
       issues = List<LifesumMeasurementIssue>.unmodifiable(issues),
       sourceRowCounts = Map<LifesumExportSection, int>.unmodifiable(
         sourceRowCounts,
       );

  final List<WeightLogEntity> weights;
  final List<BodyMeasurementLogEntity> bodyMeasurements;
  final List<LifesumMeasurementIssue> issues;
  final Map<LifesumExportSection, int> sourceRowCounts;

  int sourceRowsFor(LifesumExportSection section) =>
      sourceRowCounts[section] ?? 0;

  int get blockingIssueCount =>
      issues.where((issue) => issue.blocksSection).length;

  int get warningCount => issues.where((issue) => !issue.blocksSection).length;
}

/// Pure conversion of Lifesum measurement CSV strings into Stable entities.
///
/// This parser has no persistence dependency. Callers can preview and compare
/// the candidates with existing Stable history before choosing to apply them.
class LifesumMeasurementParser {
  static LifesumMeasurementParseResult parse({
    String? weighInsCsv,
    String? bodyMeasuresCsv,
    String? bodyFatCsv,
  }) {
    final issues = <LifesumMeasurementIssue>[];
    final sourceRowCounts = <LifesumExportSection, int>{};

    final weights = weighInsCsv == null
        ? <WeightLogEntity>[]
        : _parseWeights(weighInsCsv, issues, sourceRowCounts);
    final bodyBuilders = <int, _BodyMeasurementBuilder>{};
    if (bodyMeasuresCsv != null) {
      _parseBodyMeasures(
        bodyMeasuresCsv,
        bodyBuilders,
        issues,
        sourceRowCounts,
      );
    }
    if (bodyFatCsv != null) {
      _parseBodyFat(bodyFatCsv, bodyBuilders, issues, sourceRowCounts);
    }

    final bodyMeasurements =
        bodyBuilders.values
            .map((builder) => builder.build())
            .where((entity) => entity.hasMeasurement && entity.isValid)
            .toList()
          ..sort((left, right) => left.date.compareTo(right.date));

    return LifesumMeasurementParseResult(
      weights: weights,
      bodyMeasurements: bodyMeasurements,
      issues: issues,
      sourceRowCounts: sourceRowCounts,
    );
  }

  static List<WeightLogEntity> _parseWeights(
    String csv,
    List<LifesumMeasurementIssue> issues,
    Map<LifesumExportSection, int> sourceRowCounts,
  ) {
    final table = _CsvTable.parse(csv, LifesumExportSection.weighIns, issues);
    sourceRowCounts[LifesumExportSection.weighIns] = table.sourceRowCount;
    final byDay = <int, WeightLogEntity>{};
    final conflictingDays = <int>{};

    for (final row in table.rows) {
      final date = _parseDate(row['date']);
      if (date == null) {
        issues.add(
          LifesumMeasurementIssue(
            section: LifesumExportSection.weighIns,
            code: LifesumMeasurementIssueCode.invalidDate,
            rowNumber: row.rowNumber,
            column: 'date',
          ),
        );
        continue;
      }

      final weight = _parseFiniteDouble(row['weight_kg']);
      if (weight == null) {
        issues.add(
          LifesumMeasurementIssue(
            section: LifesumExportSection.weighIns,
            code: LifesumMeasurementIssueCode.invalidNumber,
            rowNumber: row.rowNumber,
            column: 'weight_kg',
          ),
        );
        continue;
      }
      if (weight < Ranges.minWeight || weight > Ranges.maxWeight) {
        issues.add(
          LifesumMeasurementIssue(
            section: LifesumExportSection.weighIns,
            code: LifesumMeasurementIssueCode.outOfRange,
            rowNumber: row.rowNumber,
            column: 'weight_kg',
          ),
        );
        continue;
      }

      final dayKey = _dayKey(date);
      if (conflictingDays.contains(dayKey)) {
        issues.add(
          LifesumMeasurementIssue(
            section: LifesumExportSection.weighIns,
            code: LifesumMeasurementIssueCode.conflictingSameDayValue,
            rowNumber: row.rowNumber,
            column: 'weight_kg',
          ),
        );
        continue;
      }

      final previous = byDay[dayKey];
      if (previous == null) {
        byDay[dayKey] = WeightLogEntity(date: date, weightKg: weight);
      } else if (previous.weightKg == weight) {
        issues.add(
          LifesumMeasurementIssue(
            section: LifesumExportSection.weighIns,
            code: LifesumMeasurementIssueCode.duplicateSameDayValue,
            rowNumber: row.rowNumber,
            column: 'weight_kg',
          ),
        );
      } else {
        byDay.remove(dayKey);
        conflictingDays.add(dayKey);
        issues.add(
          LifesumMeasurementIssue(
            section: LifesumExportSection.weighIns,
            code: LifesumMeasurementIssueCode.conflictingSameDayValue,
            rowNumber: row.rowNumber,
            column: 'weight_kg',
          ),
        );
      }
    }

    return byDay.values.toList()
      ..sort((left, right) => left.date.compareTo(right.date));
  }

  static void _parseBodyMeasures(
    String csv,
    Map<int, _BodyMeasurementBuilder> builders,
    List<LifesumMeasurementIssue> issues,
    Map<LifesumExportSection, int> sourceRowCounts,
  ) {
    final table = _CsvTable.parse(
      csv,
      LifesumExportSection.bodyMeasures,
      issues,
    );
    sourceRowCounts[LifesumExportSection.bodyMeasures] = table.sourceRowCount;

    for (final row in table.rows) {
      final date = _parseDate(row['date']);
      if (date == null) {
        issues.add(
          LifesumMeasurementIssue(
            section: LifesumExportSection.bodyMeasures,
            code: LifesumMeasurementIssueCode.invalidDate,
            rowNumber: row.rowNumber,
            column: 'date',
          ),
        );
        continue;
      }

      final type = _bodyMeasurementType(row['measure']);
      if (type == null) {
        issues.add(
          LifesumMeasurementIssue(
            section: LifesumExportSection.bodyMeasures,
            code: LifesumMeasurementIssueCode.unsupportedMeasurement,
            rowNumber: row.rowNumber,
            column: 'measure',
          ),
        );
        continue;
      }

      if (row['unit']?.trim().toLowerCase() != 'cm') {
        issues.add(
          LifesumMeasurementIssue(
            section: LifesumExportSection.bodyMeasures,
            code: LifesumMeasurementIssueCode.unsupportedUnit,
            rowNumber: row.rowNumber,
            column: 'unit',
          ),
        );
        continue;
      }

      final value = _parseFiniteDouble(row['value']);
      if (value == null) {
        issues.add(
          LifesumMeasurementIssue(
            section: LifesumExportSection.bodyMeasures,
            code: LifesumMeasurementIssueCode.invalidNumber,
            rowNumber: row.rowNumber,
            column: 'value',
          ),
        );
        continue;
      }
      if (value <= 0 || value > 500) {
        issues.add(
          LifesumMeasurementIssue(
            section: LifesumExportSection.bodyMeasures,
            code: LifesumMeasurementIssueCode.outOfRange,
            rowNumber: row.rowNumber,
            column: 'value',
          ),
        );
        continue;
      }

      final builder = builders.putIfAbsent(
        _dayKey(date),
        () => _BodyMeasurementBuilder(date),
      );
      _recordSetOutcome(
        builder.set(type, value),
        LifesumExportSection.bodyMeasures,
        row.rowNumber,
        'value',
        issues,
      );
    }
  }

  static void _parseBodyFat(
    String csv,
    Map<int, _BodyMeasurementBuilder> builders,
    List<LifesumMeasurementIssue> issues,
    Map<LifesumExportSection, int> sourceRowCounts,
  ) {
    final table = _CsvTable.parse(csv, LifesumExportSection.bodyFat, issues);
    sourceRowCounts[LifesumExportSection.bodyFat] = table.sourceRowCount;

    for (final row in table.rows) {
      final date = _parseDate(row['date']);
      if (date == null) {
        issues.add(
          LifesumMeasurementIssue(
            section: LifesumExportSection.bodyFat,
            code: LifesumMeasurementIssueCode.invalidDate,
            rowNumber: row.rowNumber,
            column: 'date',
          ),
        );
        continue;
      }

      final value = _parseFiniteDouble(row['bodyfat_pct']);
      if (value == null) {
        issues.add(
          LifesumMeasurementIssue(
            section: LifesumExportSection.bodyFat,
            code: LifesumMeasurementIssueCode.invalidNumber,
            rowNumber: row.rowNumber,
            column: 'bodyfat_pct',
          ),
        );
        continue;
      }
      if (value <= 0 || value > 100) {
        issues.add(
          LifesumMeasurementIssue(
            section: LifesumExportSection.bodyFat,
            code: LifesumMeasurementIssueCode.outOfRange,
            rowNumber: row.rowNumber,
            column: 'bodyfat_pct',
          ),
        );
        continue;
      }

      final builder = builders.putIfAbsent(
        _dayKey(date),
        () => _BodyMeasurementBuilder(date),
      );
      _recordSetOutcome(
        builder.set(BodyMeasurementType.bodyFat, value),
        LifesumExportSection.bodyFat,
        row.rowNumber,
        'bodyfat_pct',
        issues,
      );
    }
  }

  static void _recordSetOutcome(
    _SetOutcome outcome,
    LifesumExportSection section,
    int rowNumber,
    String column,
    List<LifesumMeasurementIssue> issues,
  ) {
    final code = switch (outcome) {
      _SetOutcome.added => null,
      _SetOutcome.duplicate =>
        LifesumMeasurementIssueCode.duplicateSameDayValue,
      _SetOutcome.conflict =>
        LifesumMeasurementIssueCode.conflictingSameDayValue,
    };
    if (code == null) return;
    issues.add(
      LifesumMeasurementIssue(
        section: section,
        code: code,
        rowNumber: rowNumber,
        column: column,
      ),
    );
  }

  static BodyMeasurementType? _bodyMeasurementType(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'waist' => BodyMeasurementType.waist,
      'hip' || 'hips' => BodyMeasurementType.hips,
      'chest' => BodyMeasurementType.chest,
      'arm' => BodyMeasurementType.arm,
      'thigh' => BodyMeasurementType.thigh,
      _ => null,
    };
  }

  static double? _parseFiniteDouble(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = double.tryParse(raw.trim());
    return value != null && value.isFinite ? value : null;
  }

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
}

class _CsvTable {
  const _CsvTable({required this.rows, required this.sourceRowCount});

  final List<_CsvRow> rows;
  final int sourceRowCount;

  static _CsvTable parse(
    String csv,
    LifesumExportSection section,
    List<LifesumMeasurementIssue> issues,
  ) {
    final lines = csv.split(RegExp(r'\r\n?|\n'));
    var headerLineIndex = -1;
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].trim().isNotEmpty) {
        headerLineIndex = index;
        break;
      }
    }

    if (headerLineIndex == -1) {
      issues.add(
        LifesumMeasurementIssue(
          section: section,
          code: LifesumMeasurementIssueCode.emptyFile,
        ),
      );
      return const _CsvTable(rows: <_CsvRow>[], sourceRowCount: 0);
    }

    final headers = CsvRowParser.splitRow(
      lines[headerLineIndex],
    ).map((header) => header.trim().toLowerCase()).toList();
    if (headers.isNotEmpty) {
      headers[0] = headers[0].replaceFirst('\ufeff', '');
    }

    final dataLines = <({int rowNumber, String value})>[];
    for (var index = headerLineIndex + 1; index < lines.length; index++) {
      if (lines[index].trim().isNotEmpty) {
        dataLines.add((rowNumber: index + 1, value: lines[index]));
      }
    }

    if (headers.toSet().length != headers.length) {
      issues.add(
        LifesumMeasurementIssue(
          section: section,
          code: LifesumMeasurementIssueCode.duplicateHeaderColumns,
        ),
      );
      return _CsvTable(
        rows: const <_CsvRow>[],
        sourceRowCount: dataLines.length,
      );
    }

    final headerSet = headers.toSet();
    final missingColumns = section.requiredColumns
        .where((column) => !headerSet.contains(column))
        .toList();
    if (missingColumns.isNotEmpty) {
      for (final column in missingColumns) {
        issues.add(
          LifesumMeasurementIssue(
            section: section,
            code: LifesumMeasurementIssueCode.missingRequiredColumns,
            column: column,
          ),
        );
      }
      return _CsvTable(
        rows: const <_CsvRow>[],
        sourceRowCount: dataLines.length,
      );
    }

    final rows = <_CsvRow>[];
    for (final dataLine in dataLines) {
      final cells = CsvRowParser.splitRow(dataLine.value);
      if (cells.length != headers.length) {
        issues.add(
          LifesumMeasurementIssue(
            section: section,
            code: LifesumMeasurementIssueCode.malformedRow,
            rowNumber: dataLine.rowNumber,
          ),
        );
        continue;
      }
      rows.add(
        _CsvRow(
          rowNumber: dataLine.rowNumber,
          values: <String, String>{
            for (var index = 0; index < headers.length; index++)
              headers[index]: cells[index],
          },
        ),
      );
    }
    return _CsvTable(rows: rows, sourceRowCount: dataLines.length);
  }
}

class _CsvRow {
  const _CsvRow({required this.rowNumber, required this.values});

  final int rowNumber;
  final Map<String, String> values;

  String? operator [](String column) => values[column];
}

enum _SetOutcome { added, duplicate, conflict }

class _BodyMeasurementBuilder {
  _BodyMeasurementBuilder(this.date);

  final DateTime date;
  final Map<BodyMeasurementType, double> _values =
      <BodyMeasurementType, double>{};
  final Set<BodyMeasurementType> _conflictingTypes = <BodyMeasurementType>{};

  _SetOutcome set(BodyMeasurementType type, double value) {
    if (_conflictingTypes.contains(type)) return _SetOutcome.conflict;
    final previous = _values[type];
    if (previous == null) {
      _values[type] = value;
      return _SetOutcome.added;
    }
    if (previous == value) return _SetOutcome.duplicate;
    _values.remove(type);
    _conflictingTypes.add(type);
    return _SetOutcome.conflict;
  }

  BodyMeasurementLogEntity build() => BodyMeasurementLogEntity(
    date: date,
    waistCm: _values[BodyMeasurementType.waist],
    hipsCm: _values[BodyMeasurementType.hips],
    chestCm: _values[BodyMeasurementType.chest],
    armCm: _values[BodyMeasurementType.arm],
    thighCm: _values[BodyMeasurementType.thigh],
    bodyFatPercent: _values[BodyMeasurementType.bodyFat],
  );
}
