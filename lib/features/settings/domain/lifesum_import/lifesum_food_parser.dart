import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/csv_row_parser.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';

enum LifesumFoodBasis { gramWeight, sourceServing, loggedTotal }

enum LifesumFoodIssueCode {
  emptyFile,
  missingRequiredColumns,
  duplicateHeaderColumns,
  malformedRow,
  missingRequiredValue,
  invalidDate,
  invalidNumber,
  nonPositiveAmount,
  negativeNutrient,
  unsupportedMealType,
  servingBasisFallback,
}

/// Row-scoped parse feedback that intentionally omits source values.
class LifesumFoodIssue {
  const LifesumFoodIssue({required this.code, this.rowNumber, this.column});

  final LifesumFoodIssueCode code;
  final int? rowNumber;
  final String? column;

  bool get blocksSection =>
      code == LifesumFoodIssueCode.emptyFile ||
      code == LifesumFoodIssueCode.missingRequiredColumns ||
      code == LifesumFoodIssueCode.duplicateHeaderColumns;
}

/// Nutrient totals exactly as they apply to one logged Lifesum row.
class LifesumLoggedNutrients {
  const LifesumLoggedNutrients({
    required this.calories,
    this.carbs,
    this.fiber,
    this.sugars,
    this.cholesterolGrams,
    this.fat,
    this.saturatedFat,
    this.unsaturatedFat,
    this.potassiumGrams,
    this.protein,
    this.sodiumGrams,
  });

  final double calories;
  final double? carbs;
  final double? fiber;
  final double? sugars;
  final double? cholesterolGrams;
  final double? fat;
  final double? saturatedFat;
  final double? unsaturatedFat;
  final double? potassiumGrams;
  final double? protein;
  final double? sodiumGrams;
}

class LifesumFoodCandidate {
  const LifesumFoodCandidate({
    required this.intake,
    required this.basis,
    required this.loggedNutrients,
    required this.sourceRowNumber,
  });

  final IntakeEntity intake;
  final LifesumFoodBasis basis;
  final LifesumLoggedNutrients loggedNutrients;
  final int sourceRowNumber;
}

/// Aggregate totals needed to reconstruct a Stable tracked day later, when
/// the active profile's historical goal policy is available.
class LifesumTrackedDayCandidate {
  const LifesumTrackedDayCandidate({
    required this.day,
    required this.intakeCount,
    required this.caloriesTracked,
    required this.carbsTracked,
    required this.fatTracked,
    required this.proteinTracked,
  });

  final DateTime day;
  final int intakeCount;
  final double caloriesTracked;
  final double carbsTracked;
  final double fatTracked;
  final double proteinTracked;
}

class LifesumFoodParseResult {
  LifesumFoodParseResult({
    required this.sourceRowCount,
    required List<LifesumFoodCandidate> candidates,
    required List<LifesumTrackedDayCandidate> trackedDays,
    required List<LifesumFoodIssue> issues,
  }) : candidates = List<LifesumFoodCandidate>.unmodifiable(candidates),
       trackedDays = List<LifesumTrackedDayCandidate>.unmodifiable(trackedDays),
       issues = List<LifesumFoodIssue>.unmodifiable(issues);

  final int sourceRowCount;
  final List<LifesumFoodCandidate> candidates;
  final List<LifesumTrackedDayCandidate> trackedDays;
  final List<LifesumFoodIssue> issues;

  List<IntakeEntity> get intakes =>
      List<IntakeEntity>.unmodifiable(candidates.map((value) => value.intake));

  int countForBasis(LifesumFoodBasis basis) =>
      candidates.where((candidate) => candidate.basis == basis).length;

  int get blockingIssueCount =>
      issues.where((issue) => issue.blocksSection).length;

  int get warningCount => issues.where((issue) => !issue.blocksSection).length;
}

/// Converts Lifesum food rows into self-contained Stable intake snapshots.
///
/// Source nutrients are totals for the logged amount. Gram-backed rows are
/// converted to a physical per-100-g basis. Rows without grams use an explicit
/// serving basis so totals remain exact without inventing a physical weight.
class LifesumFoodParser {
  static const _nutrientColumns = <String>[
    'calories',
    'carbs',
    'carbs_fiber',
    'carbs_sugar',
    'cholesterol',
    'fat',
    'fat_saturated',
    'fat_unsaturated',
    'potassium',
    'protein',
    'sodium',
  ];

  static LifesumFoodParseResult parse(
    String csv, {
    int dayStartOffsetMinutes = 0,
  }) {
    final issues = <LifesumFoodIssue>[];
    final table = _FoodCsvTable.parse(csv, issues);
    final candidates = <LifesumFoodCandidate>[];
    final trackedDayBuilders = <int, _TrackedDayBuilder>{};
    final occurrenceCounts = <String, int>{};
    final offsetMinutes =
        dayStartOffsetMinutes >= 0 && dayStartOffsetMinutes < 24 * 60
        ? dayStartOffsetMinutes
        : 0;

    for (final row in table.rows) {
      final date = _parseDate(row['date']);
      if (date == null) {
        issues.add(
          LifesumFoodIssue(
            code: LifesumFoodIssueCode.invalidDate,
            rowNumber: row.rowNumber,
            column: 'date',
          ),
        );
        continue;
      }

      final intakeType = _parseMealType(row['meal_type']);
      if (intakeType == null) {
        issues.add(
          LifesumFoodIssue(
            code: LifesumFoodIssueCode.unsupportedMealType,
            rowNumber: row.rowNumber,
            column: 'meal_type',
          ),
        );
        continue;
      }

      final title = row['title']?.trim() ?? '';
      final servingName = row['serving_name']?.trim() ?? '';
      if (title.isEmpty || servingName.isEmpty) {
        issues.add(
          LifesumFoodIssue(
            code: LifesumFoodIssueCode.missingRequiredValue,
            rowNumber: row.rowNumber,
            column: title.isEmpty ? 'title' : 'serving_name',
          ),
        );
        continue;
      }

      final sourceAmount = _parseFiniteDouble(row['amount']);
      if (sourceAmount == null) {
        issues.add(
          LifesumFoodIssue(
            code: LifesumFoodIssueCode.invalidNumber,
            rowNumber: row.rowNumber,
            column: 'amount',
          ),
        );
        continue;
      }
      if (sourceAmount <= 0) {
        issues.add(
          LifesumFoodIssue(
            code: LifesumFoodIssueCode.nonPositiveAmount,
            rowNumber: row.rowNumber,
            column: 'amount',
          ),
        );
        continue;
      }

      final gramText = row['amount_in_grams']?.trim() ?? '';
      double? gramWeight;
      if (gramText.isNotEmpty) {
        gramWeight = _parseFiniteDouble(gramText);
        if (gramWeight == null) {
          issues.add(
            LifesumFoodIssue(
              code: LifesumFoodIssueCode.invalidNumber,
              rowNumber: row.rowNumber,
              column: 'amount_in_grams',
            ),
          );
          continue;
        }
        if (gramWeight <= 0) {
          issues.add(
            LifesumFoodIssue(
              code: LifesumFoodIssueCode.nonPositiveAmount,
              rowNumber: row.rowNumber,
              column: 'amount_in_grams',
            ),
          );
          continue;
        }
      }

      final nutrientValues = <String, double?>{};
      String? invalidNutrientColumn;
      LifesumFoodIssueCode? invalidNutrientCode;
      for (final column in _nutrientColumns) {
        final raw = row[column]?.trim() ?? '';
        if (raw.isEmpty) {
          nutrientValues[column] = null;
          continue;
        }
        final value = _parseFiniteDouble(raw);
        if (value == null) {
          invalidNutrientColumn = column;
          invalidNutrientCode = LifesumFoodIssueCode.invalidNumber;
          break;
        }
        if (value < 0) {
          invalidNutrientColumn = column;
          invalidNutrientCode = LifesumFoodIssueCode.negativeNutrient;
          break;
        }
        nutrientValues[column] = value;
      }
      if (invalidNutrientCode != null) {
        issues.add(
          LifesumFoodIssue(
            code: invalidNutrientCode,
            rowNumber: row.rowNumber,
            column: invalidNutrientColumn,
          ),
        );
        continue;
      }
      final calories = nutrientValues['calories'];
      if (calories == null) {
        issues.add(
          LifesumFoodIssue(
            code: LifesumFoodIssueCode.missingRequiredValue,
            rowNumber: row.rowNumber,
            column: 'calories',
          ),
        );
        continue;
      }

      final lowerServingName = servingName.toLowerCase();
      final basis = gramWeight != null
          ? LifesumFoodBasis.gramWeight
          : lowerServingName == 'calories'
          ? LifesumFoodBasis.loggedTotal
          : LifesumFoodBasis.sourceServing;
      final intakeAmount = switch (basis) {
        LifesumFoodBasis.gramWeight => gramWeight!,
        LifesumFoodBasis.sourceServing => sourceAmount,
        LifesumFoodBasis.loggedTotal => 1.0,
      };
      if (basis != LifesumFoodBasis.gramWeight) {
        issues.add(
          LifesumFoodIssue(
            code: LifesumFoodIssueCode.servingBasisFallback,
            rowNumber: row.rowNumber,
            column: 'amount_in_grams',
          ),
        );
      }

      double? per100(String column, {bool sourceGramsToMilligrams = false}) {
        final total = nutrientValues[column];
        if (total == null) return null;
        final convertedTotal = sourceGramsToMilligrams ? total * 1000 : total;
        return convertedTotal * 100 / intakeAmount;
      }

      final nutriments = MealNutrimentsEntity(
        energyKcal100: per100('calories'),
        carbohydrates100: per100('carbs'),
        fat100: per100('fat'),
        proteins100: per100('protein'),
        sugars100: per100('carbs_sugar'),
        saturatedFat100: per100('fat_saturated'),
        fiber100: per100('carbs_fiber'),
        // Lifesum exports only total unsaturated fat, while Stable stores
        // mono/poly separately. Leave both empty instead of inventing a split.
        cholesterol100: per100('cholesterol', sourceGramsToMilligrams: true),
        sodium100: per100('sodium', sourceGramsToMilligrams: true),
        potassium100: per100('potassium', sourceGramsToMilligrams: true),
      );

      final canonicalRow = LifesumExportSection.food.requiredColumns
          .map((column) => row[column]?.trim() ?? '')
          .join('\u001f');
      final occurrence = occurrenceCounts.update(
        canonicalRow,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      final intakeId =
          'lifesum-intake-${_stableDigest(canonicalRow)}-'
          '${occurrence.toString().padLeft(3, '0')}';
      final brand = row['brand']?.trim();
      final mealSignature = <String>[
        title.toLowerCase(),
        (brand ?? '').toLowerCase(),
        servingName.toLowerCase(),
        basis.name,
        for (final column in _nutrientColumns)
          nutrientValues[column]?.toString() ?? '',
        gramWeight?.toString() ?? '',
        sourceAmount.toString(),
      ].join('\u001f');
      final isPlainGramServing = _isPlainGramServing(servingName);
      final meal = MealEntity(
        code: 'lifesum-meal-${_stableDigest(mealSignature)}',
        name: title,
        brands: brand == null || brand.isEmpty ? null : brand,
        url: null,
        mealQuantity: null,
        mealUnit: basis == LifesumFoodBasis.gramWeight ? 'g' : 'serving',
        servingQuantity: basis == LifesumFoodBasis.gramWeight
            ? isPlainGramServing
                  ? null
                  : gramWeight! / sourceAmount
            : 1,
        servingUnit: basis == LifesumFoodBasis.gramWeight
            ? isPlainGramServing
                  ? null
                  : 'g'
            : 'serving',
        servingSize: isPlainGramServing ? null : servingName,
        nutriments: nutriments,
        source: MealSourceEntity.custom,
        detailed: true,
      );
      final intake = IntakeEntity(
        id: intakeId,
        unit: meal.mealUnit!,
        amount: intakeAmount,
        type: intakeType,
        meal: meal,
        dateTime: DateTime(date.year, date.month, date.day).add(
          Duration(
            minutes: offsetMinutes + 12 * 60,
            microseconds: row.rowNumber,
          ),
        ),
      );
      final loggedNutrients = LifesumLoggedNutrients(
        calories: calories,
        carbs: nutrientValues['carbs'],
        fiber: nutrientValues['carbs_fiber'],
        sugars: nutrientValues['carbs_sugar'],
        cholesterolGrams: nutrientValues['cholesterol'],
        fat: nutrientValues['fat'],
        saturatedFat: nutrientValues['fat_saturated'],
        unsaturatedFat: nutrientValues['fat_unsaturated'],
        potassiumGrams: nutrientValues['potassium'],
        protein: nutrientValues['protein'],
        sodiumGrams: nutrientValues['sodium'],
      );
      final candidate = LifesumFoodCandidate(
        intake: intake,
        basis: basis,
        loggedNutrients: loggedNutrients,
        sourceRowNumber: row.rowNumber,
      );
      candidates.add(candidate);
      trackedDayBuilders
          .putIfAbsent(_dayKey(date), () => _TrackedDayBuilder(date))
          .add(loggedNutrients);
    }

    final trackedDays =
        trackedDayBuilders.values.map((builder) => builder.build()).toList()
          ..sort((left, right) => left.day.compareTo(right.day));
    return LifesumFoodParseResult(
      sourceRowCount: table.sourceRowCount,
      candidates: candidates,
      trackedDays: trackedDays,
      issues: issues,
    );
  }

  static IntakeTypeEntity? _parseMealType(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'breakfast' => IntakeTypeEntity.breakfast,
      'lunch' => IntakeTypeEntity.lunch,
      'dinner' => IntakeTypeEntity.dinner,
      'snack' => IntakeTypeEntity.snack,
      _ => null,
    };
  }

  static bool _isPlainGramServing(String value) {
    return switch (value.trim().toLowerCase()) {
      'g' || 'gram' || 'grams' => true,
      _ => false,
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

  /// Two independent 32-bit hashes keep generated IDs stable on Dart VM and
  /// web without adding a crypto dependency or retaining source text in IDs.
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

class _FoodCsvTable {
  const _FoodCsvTable({required this.rows, required this.sourceRowCount});

  final List<_FoodCsvRow> rows;
  final int sourceRowCount;

  static _FoodCsvTable parse(String csv, List<LifesumFoodIssue> issues) {
    final lines = csv.split(RegExp(r'\r\n?|\n'));
    var headerIndex = -1;
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].trim().isNotEmpty) {
        headerIndex = index;
        break;
      }
    }
    if (headerIndex == -1) {
      issues.add(const LifesumFoodIssue(code: LifesumFoodIssueCode.emptyFile));
      return const _FoodCsvTable(rows: <_FoodCsvRow>[], sourceRowCount: 0);
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
        const LifesumFoodIssue(
          code: LifesumFoodIssueCode.duplicateHeaderColumns,
        ),
      );
      return _FoodCsvTable(
        rows: const <_FoodCsvRow>[],
        sourceRowCount: dataLines.length,
      );
    }
    final headerSet = headers.toSet();
    final missing = LifesumExportSection.food.requiredColumns.where(
      (column) => !headerSet.contains(column),
    );
    if (missing.isNotEmpty) {
      for (final column in missing) {
        issues.add(
          LifesumFoodIssue(
            code: LifesumFoodIssueCode.missingRequiredColumns,
            column: column,
          ),
        );
      }
      return _FoodCsvTable(
        rows: const <_FoodCsvRow>[],
        sourceRowCount: dataLines.length,
      );
    }

    final rows = <_FoodCsvRow>[];
    for (final dataLine in dataLines) {
      final values = CsvRowParser.splitRow(dataLine.value);
      if (values.length != headers.length) {
        issues.add(
          LifesumFoodIssue(
            code: LifesumFoodIssueCode.malformedRow,
            rowNumber: dataLine.rowNumber,
          ),
        );
        continue;
      }
      rows.add(
        _FoodCsvRow(
          rowNumber: dataLine.rowNumber,
          values: <String, String>{
            for (var index = 0; index < headers.length; index++)
              headers[index]: values[index],
          },
        ),
      );
    }
    return _FoodCsvTable(rows: rows, sourceRowCount: dataLines.length);
  }
}

class _FoodCsvRow {
  const _FoodCsvRow({required this.rowNumber, required this.values});

  final int rowNumber;
  final Map<String, String> values;

  String? operator [](String column) => values[column];
}

class _TrackedDayBuilder {
  _TrackedDayBuilder(this.day);

  final DateTime day;
  var intakeCount = 0;
  var calories = 0.0;
  var carbs = 0.0;
  var fat = 0.0;
  var protein = 0.0;

  void add(LifesumLoggedNutrients nutrients) {
    intakeCount++;
    calories += nutrients.calories;
    carbs += nutrients.carbs ?? 0;
    fat += nutrients.fat ?? 0;
    protein += nutrients.protein ?? 0;
  }

  LifesumTrackedDayCandidate build() => LifesumTrackedDayCandidate(
    day: day,
    intakeCount: intakeCount,
    caloriesTracked: calories,
    carbsTracked: carbs,
    fatTracked: fat,
    proteinTracked: protein,
  );
}
