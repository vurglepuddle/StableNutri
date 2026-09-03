import 'package:opennutritracker/core/utils/csv_row_parser.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';

enum LifesumRecipeIssueCode {
  emptyFile,
  missingRequiredColumns,
  duplicateHeaderColumns,
  malformedRow,
  orphanIngredient,
  missingRequiredValue,
  invalidServings,
  invalidCreatedAt,
  invalidNumber,
  negativeNutrient,
  nonPositiveIngredientAmount,
  unexpectedContinuationRecipeData,
  recipeWithoutIngredients,
}

/// Value-free structural feedback. Recipe and ingredient text and nutrition
/// values are intentionally absent from issues.
class LifesumRecipeIssue {
  const LifesumRecipeIssue({required this.code, this.rowNumber, this.column});

  final LifesumRecipeIssueCode code;
  final int? rowNumber;
  final String? column;

  bool get blocksSection =>
      code == LifesumRecipeIssueCode.emptyFile ||
      code == LifesumRecipeIssueCode.missingRequiredColumns ||
      code == LifesumRecipeIssueCode.duplicateHeaderColumns;
}

/// Nutrients exactly as logged on the Lifesum recipe start row.
///
/// The export does not identify a physical-weight basis, so these values are
/// not relabelled as Stable per-100-g nutrition. Mineral values retain the
/// source's gram scale until a snapshot-capable persistence model exists.
class LifesumRecipeLoggedNutrients {
  const LifesumRecipeLoggedNutrients({
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

/// A display-faithful ingredient descriptor. No mass or ingredient nutrition
/// exists in the source export, so neither is synthesized here.
class LifesumRecipeIngredientCandidate {
  const LifesumRecipeIngredientCandidate({
    required this.id,
    required this.title,
    required this.brand,
    required this.servingName,
    required this.amount,
    required this.sourceRowNumber,
  });

  final String id;
  final String title;
  final String? brand;
  final String servingName;
  final double amount;
  final int sourceRowNumber;

  double? get physicalWeightGrams => null;
}

/// A normalized source snapshot, deliberately not a `RecipeEntity`. Stable's
/// current recipe entity requires gram weight and per-100-g nutrition, neither
/// of which can be recovered from this archive without fabrication.
class LifesumRecipeCandidate {
  LifesumRecipeCandidate({
    required this.id,
    required this.title,
    required this.description,
    required this.servingsCount,
    required this.createdAt,
    required this.loggedNutrients,
    required List<LifesumRecipeIngredientCandidate> ingredients,
    required this.sourceStartRowNumber,
  }) : ingredients = List<LifesumRecipeIngredientCandidate>.unmodifiable(
         ingredients,
       );

  final String id;
  final String title;
  final String? description;
  final int servingsCount;
  final DateTime createdAt;
  final LifesumRecipeLoggedNutrients loggedNutrients;
  final List<LifesumRecipeIngredientCandidate> ingredients;
  final int sourceStartRowNumber;

  bool get requiresSnapshotPersistence => true;
  double? get physicalWeightGrams => null;
}

class LifesumRecipeParseResult {
  LifesumRecipeParseResult({
    required this.sourceRowCount,
    required List<LifesumRecipeCandidate> candidates,
    required List<LifesumRecipeIssue> issues,
  }) : candidates = List<LifesumRecipeCandidate>.unmodifiable(candidates),
       issues = List<LifesumRecipeIssue>.unmodifiable(issues);

  final int sourceRowCount;
  final List<LifesumRecipeCandidate> candidates;
  final List<LifesumRecipeIssue> issues;

  int get ingredientCount => candidates.fold<int>(
    0,
    (sum, candidate) => sum + candidate.ingredients.length,
  );

  int get blockingIssueCount =>
      issues.where((issue) => issue.blocksSection).length;

  int get warningCount => issues.where((issue) => !issue.blocksSection).length;
}

/// Groups Lifesum's start/continuation rows into honest recipe snapshots.
class LifesumRecipeParser {
  static const _recipeContinuationColumns = <String>[
    'description',
    'servings',
    'created',
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

  static const _ingredientColumns = <String>[
    'ingredient_title',
    'ingredient_brand',
    'ingredient_serving_name',
    'ingredient_amount',
  ];

  static LifesumRecipeParseResult parse(String csv) {
    final issues = <LifesumRecipeIssue>[];
    final table = _RecipeCsvTable.parse(csv, issues);
    final pendingRecipes = <_PendingRecipe>[];
    _PendingRecipe? current;

    for (final row in table.rows) {
      final title = row['title']?.trim() ?? '';
      if (title.isNotEmpty) {
        current = _parseRecipeStart(row, title, issues);
        if (current != null) pendingRecipes.add(current);
      } else {
        if (current == null) {
          issues.add(
            LifesumRecipeIssue(
              code: LifesumRecipeIssueCode.orphanIngredient,
              rowNumber: row.rowNumber,
              column: 'title',
            ),
          );
          continue;
        }
        current.canonicalRows.add(_canonicalRow(row));
        final unexpectedColumn = _recipeContinuationColumns
            .where((column) => (row[column]?.trim() ?? '').isNotEmpty)
            .firstOrNull;
        if (unexpectedColumn != null) {
          issues.add(
            LifesumRecipeIssue(
              code: LifesumRecipeIssueCode.unexpectedContinuationRecipeData,
              rowNumber: row.rowNumber,
              column: unexpectedColumn,
            ),
          );
        }
      }

      if (current != null) {
        final ingredient = _parseIngredient(row, issues);
        if (ingredient != null) current.ingredients.add(ingredient);
      }
    }

    final candidates = <LifesumRecipeCandidate>[];
    final recipeOccurrences = <String, int>{};
    for (final pending in pendingRecipes) {
      if (pending.ingredients.isEmpty) {
        issues.add(
          LifesumRecipeIssue(
            code: LifesumRecipeIssueCode.recipeWithoutIngredients,
            rowNumber: pending.sourceStartRowNumber,
            column: 'ingredient_title',
          ),
        );
        continue;
      }
      final signature = pending.canonicalRows.join('\u001e');
      final occurrence = recipeOccurrences.update(
        signature,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      final recipeId =
          'lifesum-recipe-${_stableDigest(signature)}-'
          '${occurrence.toString().padLeft(3, '0')}';
      final ingredientOccurrences = <String, int>{};
      final ingredients = pending.ingredients.map((ingredient) {
        final ingredientOccurrence = ingredientOccurrences.update(
          ingredient.canonicalRow,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        return LifesumRecipeIngredientCandidate(
          id:
              '$recipeId-ingredient-${_stableDigest(ingredient.canonicalRow)}-'
              '${ingredientOccurrence.toString().padLeft(3, '0')}',
          title: ingredient.title,
          brand: ingredient.brand,
          servingName: ingredient.servingName,
          amount: ingredient.amount,
          sourceRowNumber: ingredient.sourceRowNumber,
        );
      }).toList();
      candidates.add(
        LifesumRecipeCandidate(
          id: recipeId,
          title: pending.title,
          description: pending.description,
          servingsCount: pending.servingsCount,
          createdAt: pending.createdAt,
          loggedNutrients: pending.loggedNutrients,
          ingredients: ingredients,
          sourceStartRowNumber: pending.sourceStartRowNumber,
        ),
      );
    }

    return LifesumRecipeParseResult(
      sourceRowCount: table.sourceRowCount,
      candidates: candidates,
      issues: issues,
    );
  }

  static _PendingRecipe? _parseRecipeStart(
    _RecipeCsvRow row,
    String title,
    List<LifesumRecipeIssue> issues,
  ) {
    final servings = _parsePositiveInt(row['servings']);
    if (servings == null) {
      issues.add(
        LifesumRecipeIssue(
          code: LifesumRecipeIssueCode.invalidServings,
          rowNumber: row.rowNumber,
          column: 'servings',
        ),
      );
      return null;
    }
    final createdAt = _parseCreatedAt(row['created']);
    if (createdAt == null) {
      issues.add(
        LifesumRecipeIssue(
          code: LifesumRecipeIssueCode.invalidCreatedAt,
          rowNumber: row.rowNumber,
          column: 'created',
        ),
      );
      return null;
    }

    final nutrientValues = <String, double?>{};
    for (final column in _nutrientColumns) {
      final raw = row[column]?.trim() ?? '';
      if (raw.isEmpty) {
        nutrientValues[column] = null;
        continue;
      }
      final value = _parseFiniteDouble(raw);
      if (value == null) {
        issues.add(
          LifesumRecipeIssue(
            code: LifesumRecipeIssueCode.invalidNumber,
            rowNumber: row.rowNumber,
            column: column,
          ),
        );
        return null;
      }
      if (value < 0) {
        issues.add(
          LifesumRecipeIssue(
            code: LifesumRecipeIssueCode.negativeNutrient,
            rowNumber: row.rowNumber,
            column: column,
          ),
        );
        return null;
      }
      nutrientValues[column] = value;
    }
    final calories = nutrientValues['calories'];
    if (calories == null) {
      issues.add(
        LifesumRecipeIssue(
          code: LifesumRecipeIssueCode.missingRequiredValue,
          rowNumber: row.rowNumber,
          column: 'calories',
        ),
      );
      return null;
    }

    final description = row['description']?.trim();
    return _PendingRecipe(
      title: title,
      description: description == null || description.isEmpty
          ? null
          : description,
      servingsCount: servings,
      createdAt: createdAt,
      loggedNutrients: LifesumRecipeLoggedNutrients(
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
      ),
      sourceStartRowNumber: row.rowNumber,
      canonicalRows: <String>[_canonicalRow(row)],
    );
  }

  static _PendingIngredient? _parseIngredient(
    _RecipeCsvRow row,
    List<LifesumRecipeIssue> issues,
  ) {
    final title = row['ingredient_title']?.trim() ?? '';
    final servingName = row['ingredient_serving_name']?.trim() ?? '';
    if (title.isEmpty || servingName.isEmpty) {
      issues.add(
        LifesumRecipeIssue(
          code: LifesumRecipeIssueCode.missingRequiredValue,
          rowNumber: row.rowNumber,
          column: title.isEmpty
              ? 'ingredient_title'
              : 'ingredient_serving_name',
        ),
      );
      return null;
    }
    final amount = _parseFiniteDouble(row['ingredient_amount']);
    if (amount == null) {
      issues.add(
        LifesumRecipeIssue(
          code: LifesumRecipeIssueCode.invalidNumber,
          rowNumber: row.rowNumber,
          column: 'ingredient_amount',
        ),
      );
      return null;
    }
    if (amount <= 0) {
      issues.add(
        LifesumRecipeIssue(
          code: LifesumRecipeIssueCode.nonPositiveIngredientAmount,
          rowNumber: row.rowNumber,
          column: 'ingredient_amount',
        ),
      );
      return null;
    }
    final brand = row['ingredient_brand']?.trim();
    return _PendingIngredient(
      title: title,
      brand: brand == null || brand.isEmpty ? null : brand,
      servingName: servingName,
      amount: amount,
      sourceRowNumber: row.rowNumber,
      canonicalRow: _ingredientColumns
          .map((column) => row[column]?.trim() ?? '')
          .join('\u001f'),
    );
  }

  static int? _parsePositiveInt(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = double.tryParse(raw.trim());
    if (value == null || !value.isFinite || value <= 0 || value % 1 != 0) {
      return null;
    }
    return value.toInt();
  }

  static double? _parseFiniteDouble(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final value = double.tryParse(raw.trim());
    return value != null && value.isFinite ? value : null;
  }

  static DateTime? _parseCreatedAt(String? raw) {
    if (raw == null) return null;
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2}) '
      r'([+-])(\d{2})(\d{2}) UTC$',
    ).firstMatch(raw.trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    if (year < 1900 || year > 2200) return null;
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    final offsetHour = int.parse(match.group(8)!);
    final offsetMinute = int.parse(match.group(9)!);
    final calendarCheck = DateTime.utc(year, month, day);
    if (calendarCheck.year != year ||
        calendarCheck.month != month ||
        calendarCheck.day != day ||
        hour > 23 ||
        minute > 59 ||
        second > 59 ||
        offsetHour > 23 ||
        offsetMinute > 59) {
      return null;
    }
    final normalized =
        '${match.group(1)}-${match.group(2)}-${match.group(3)}T'
        '${match.group(4)}:${match.group(5)}:${match.group(6)}'
        '${match.group(7)}${match.group(8)}:${match.group(9)}';
    try {
      return DateTime.parse(normalized);
    } on FormatException {
      return null;
    }
  }

  static String _canonicalRow(_RecipeCsvRow row) => LifesumExportSection
      .recipes
      .requiredColumns
      .map((column) => row[column]?.trim() ?? '')
      .join('\u001f');

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

class _RecipeCsvTable {
  const _RecipeCsvTable({required this.rows, required this.sourceRowCount});

  final List<_RecipeCsvRow> rows;
  final int sourceRowCount;

  static _RecipeCsvTable parse(String csv, List<LifesumRecipeIssue> issues) {
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
        const LifesumRecipeIssue(code: LifesumRecipeIssueCode.emptyFile),
      );
      return const _RecipeCsvTable(rows: <_RecipeCsvRow>[], sourceRowCount: 0);
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
        const LifesumRecipeIssue(
          code: LifesumRecipeIssueCode.duplicateHeaderColumns,
        ),
      );
      return _RecipeCsvTable(
        rows: const <_RecipeCsvRow>[],
        sourceRowCount: dataLines.length,
      );
    }
    final headerSet = headers.toSet();
    final missing = LifesumExportSection.recipes.requiredColumns.where(
      (column) => !headerSet.contains(column),
    );
    if (missing.isNotEmpty) {
      for (final column in missing) {
        issues.add(
          LifesumRecipeIssue(
            code: LifesumRecipeIssueCode.missingRequiredColumns,
            column: column,
          ),
        );
      }
      return _RecipeCsvTable(
        rows: const <_RecipeCsvRow>[],
        sourceRowCount: dataLines.length,
      );
    }

    final rows = <_RecipeCsvRow>[];
    for (final dataLine in dataLines) {
      final values = CsvRowParser.splitRow(dataLine.value);
      if (values.length != headers.length) {
        issues.add(
          LifesumRecipeIssue(
            code: LifesumRecipeIssueCode.malformedRow,
            rowNumber: dataLine.rowNumber,
          ),
        );
        continue;
      }
      rows.add(
        _RecipeCsvRow(
          rowNumber: dataLine.rowNumber,
          values: <String, String>{
            for (var index = 0; index < headers.length; index++)
              headers[index]: values[index],
          },
        ),
      );
    }
    return _RecipeCsvTable(rows: rows, sourceRowCount: dataLines.length);
  }
}

class _RecipeCsvRow {
  const _RecipeCsvRow({required this.rowNumber, required this.values});

  final int rowNumber;
  final Map<String, String> values;

  String? operator [](String column) => values[column];
}

class _PendingRecipe {
  _PendingRecipe({
    required this.title,
    required this.description,
    required this.servingsCount,
    required this.createdAt,
    required this.loggedNutrients,
    required this.sourceStartRowNumber,
    required this.canonicalRows,
  });

  final String title;
  final String? description;
  final int servingsCount;
  final DateTime createdAt;
  final LifesumRecipeLoggedNutrients loggedNutrients;
  final int sourceStartRowNumber;
  final List<String> canonicalRows;
  final List<_PendingIngredient> ingredients = <_PendingIngredient>[];
}

class _PendingIngredient {
  const _PendingIngredient({
    required this.title,
    required this.brand,
    required this.servingName,
    required this.amount,
    required this.sourceRowNumber,
    required this.canonicalRow,
  });

  final String title;
  final String? brand;
  final String servingName;
  final double amount;
  final int sourceRowNumber;
  final String canonicalRow;
}
