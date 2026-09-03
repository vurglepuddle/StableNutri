import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:opennutritracker/core/utils/csv_row_parser.dart';

/// The parts of a Lifesum GDPR export that Stable understands.
enum LifesumExportSection {
  food(
    fileName: 'food.csv',
    requiredColumns: <String>[
      'date',
      'meal_type',
      'title',
      'brand',
      'serving_name',
      'amount',
      'amount_in_grams',
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
    ],
  ),
  weighIns(
    fileName: 'weighins.csv',
    requiredColumns: <String>[
      'date',
      'weight_kg',
      'height_cm',
      'goal_weight_kg',
    ],
  ),
  bodyFat(
    fileName: 'bodyfat.csv',
    requiredColumns: <String>['date', 'bodyfat_pct'],
  ),
  bodyMeasures(
    fileName: 'bodymeasures.csv',
    requiredColumns: <String>['date', 'measure', 'value', 'unit'],
  ),
  recipes(
    fileName: 'recipes.csv',
    requiredColumns: <String>[
      'title',
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
      'ingredient_title',
      'ingredient_brand',
      'ingredient_serving_name',
      'ingredient_amount',
    ],
  ),
  exercise(
    fileName: 'exercise.csv',
    requiredColumns: <String>[
      'date',
      'title',
      'duration_min',
      'calories_burned',
      'source',
    ],
  );

  const LifesumExportSection({
    required this.fileName,
    required this.requiredColumns,
  });

  final String fileName;
  final List<String> requiredColumns;
}

enum LifesumSchemaStatus {
  ready,
  missingRequiredColumns,
  unreadableHeader,
  headerTooLong,
  duplicateColumns,
}

/// Schema-only information about one supported file.
///
/// No row values or unknown archive paths are retained by the inspection.
class LifesumArchiveEntry {
  const LifesumArchiveEntry({
    required this.section,
    required this.compressedSizeBytes,
    required this.uncompressedSizeBytes,
    required this.schemaStatus,
    this.missingColumns = const <String>[],
  });

  final LifesumExportSection section;
  final int compressedSizeBytes;
  final int uncompressedSizeBytes;
  final LifesumSchemaStatus schemaStatus;
  final List<String> missingColumns;

  bool get hasValidSchema => schemaStatus == LifesumSchemaStatus.ready;
}

/// Aggregate, non-sensitive inventory of a Lifesum archive.
class LifesumArchiveInspection {
  LifesumArchiveInspection({
    required this.archiveSizeBytes,
    required this.fileCount,
    required this.directoryCount,
    required this.totalUncompressedSizeBytes,
    required this.ignoredFileCount,
    required this.ignoredUncompressedSizeBytes,
    required List<LifesumArchiveEntry> recognizedEntries,
    required Set<LifesumExportSection> duplicateSections,
  }) : recognizedEntries = List<LifesumArchiveEntry>.unmodifiable(
         recognizedEntries,
       ),
       duplicateSections = Set<LifesumExportSection>.unmodifiable(
         duplicateSections,
       );

  final int archiveSizeBytes;
  final int fileCount;
  final int directoryCount;
  final int totalUncompressedSizeBytes;
  final int ignoredFileCount;
  final int ignoredUncompressedSizeBytes;
  final List<LifesumArchiveEntry> recognizedEntries;
  final Set<LifesumExportSection> duplicateSections;

  Set<LifesumExportSection> get presentSections =>
      recognizedEntries.map((entry) => entry.section).toSet();

  Set<LifesumExportSection> get missingSections => LifesumExportSection.values
      .where((section) => !presentSections.contains(section))
      .toSet();

  Set<LifesumExportSection> get importableSections => recognizedEntries
      .where(
        (entry) =>
            entry.hasValidSchema && !duplicateSections.contains(entry.section),
      )
      .map((entry) => entry.section)
      .toSet();
}

enum LifesumArchiveFailure {
  fileNotFound,
  invalidArchive,
  tooManyEntries,
  entryTooLarge,
  archiveTooLarge,
}

class LifesumArchiveReadException implements Exception {
  const LifesumArchiveReadException(this.failure);

  final LifesumArchiveFailure failure;

  @override
  String toString() => 'Lifesum archive could not be inspected: $failure';
}

/// Reads a ZIP through a bounded file-backed stream and validates only the
/// header row of recognized Lifesum CSVs.
///
/// The ZIP is never extracted. Unknown files are represented only by aggregate
/// counts and sizes, and only a small prefix of each recognized CSV is retained
/// while its compressed stream is checked.
class LifesumArchiveReader {
  const LifesumArchiveReader({
    this.maxEntries = 512,
    this.maxEntrySizeBytes = 256 * 1024 * 1024,
    this.maxTotalUncompressedSizeBytes = 512 * 1024 * 1024,
    this.maxHeaderSizeBytes = 16 * 1024,
  });

  final int maxEntries;
  final int maxEntrySizeBytes;
  final int maxTotalUncompressedSizeBytes;
  final int maxHeaderSizeBytes;

  LifesumArchiveInspection inspectPath(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw const LifesumArchiveReadException(
        LifesumArchiveFailure.fileNotFound,
      );
    }

    InputFileStream? input;
    try {
      final archiveSizeBytes = file.lengthSync();
      input = InputFileStream(path);
      final archive = ZipDecoder().decodeStream(input);
      return _inspectArchive(archive, archiveSizeBytes);
    } on LifesumArchiveReadException {
      rethrow;
    } on Object {
      throw const LifesumArchiveReadException(
        LifesumArchiveFailure.invalidArchive,
      );
    } finally {
      input?.closeSync();
    }
  }

  LifesumArchiveInspection _inspectArchive(
    Archive archive,
    int archiveSizeBytes,
  ) {
    if (archive.length > maxEntries) {
      throw const LifesumArchiveReadException(
        LifesumArchiveFailure.tooManyEntries,
      );
    }

    var fileCount = 0;
    var directoryCount = 0;
    var totalUncompressedSizeBytes = 0;
    var ignoredFileCount = 0;
    var ignoredUncompressedSizeBytes = 0;
    final recognizedEntries = <LifesumArchiveEntry>[];
    final sectionCounts = <LifesumExportSection, int>{};

    for (final entry in archive) {
      if (!entry.isFile) {
        directoryCount++;
        continue;
      }

      fileCount++;
      if (entry.size < 0 || entry.size > maxEntrySizeBytes) {
        throw const LifesumArchiveReadException(
          LifesumArchiveFailure.entryTooLarge,
        );
      }

      totalUncompressedSizeBytes += entry.size;
      if (totalUncompressedSizeBytes > maxTotalUncompressedSizeBytes) {
        throw const LifesumArchiveReadException(
          LifesumArchiveFailure.archiveTooLarge,
        );
      }

      final section = _sectionForFlatPath(entry.name);
      if (section == null) {
        ignoredFileCount++;
        ignoredUncompressedSizeBytes += entry.size;
        continue;
      }

      sectionCounts.update(section, (count) => count + 1, ifAbsent: () => 1);
      recognizedEntries.add(_inspectEntry(entry, section));
    }

    final duplicateSections = sectionCounts.entries
        .where((entry) => entry.value > 1)
        .map((entry) => entry.key)
        .toSet();

    return LifesumArchiveInspection(
      archiveSizeBytes: archiveSizeBytes,
      fileCount: fileCount,
      directoryCount: directoryCount,
      totalUncompressedSizeBytes: totalUncompressedSizeBytes,
      ignoredFileCount: ignoredFileCount,
      ignoredUncompressedSizeBytes: ignoredUncompressedSizeBytes,
      recognizedEntries: recognizedEntries,
      duplicateSections: duplicateSections,
    );
  }

  LifesumArchiveEntry _inspectEntry(
    ArchiveFile entry,
    LifesumExportSection section,
  ) {
    final output = _HeaderCaptureOutput(maxHeaderSizeBytes, maxEntrySizeBytes);
    try {
      entry.writeContent(output, freeMemory: true);
    } on _ExpandedEntryTooLarge {
      throw const LifesumArchiveReadException(
        LifesumArchiveFailure.entryTooLarge,
      );
    } on Object {
      return LifesumArchiveEntry(
        section: section,
        compressedSizeBytes: _compressedSizeOf(entry),
        uncompressedSizeBytes: entry.size,
        schemaStatus: LifesumSchemaStatus.unreadableHeader,
      );
    }

    if (output.exceededLimit) {
      return LifesumArchiveEntry(
        section: section,
        compressedSizeBytes: _compressedSizeOf(entry),
        uncompressedSizeBytes: entry.size,
        schemaStatus: LifesumSchemaStatus.headerTooLong,
      );
    }

    late final String header;
    try {
      header = utf8.decode(output.headerBytes, allowMalformed: false);
    } on FormatException {
      return LifesumArchiveEntry(
        section: section,
        compressedSizeBytes: _compressedSizeOf(entry),
        uncompressedSizeBytes: entry.size,
        schemaStatus: LifesumSchemaStatus.unreadableHeader,
      );
    }

    final columns = CsvRowParser.splitRow(
      header,
    ).map((column) => column.trim().toLowerCase()).toList();
    if (columns.isNotEmpty) {
      columns[0] = columns[0].replaceFirst('\ufeff', '');
    }

    if (columns.toSet().length != columns.length) {
      return LifesumArchiveEntry(
        section: section,
        compressedSizeBytes: _compressedSizeOf(entry),
        uncompressedSizeBytes: entry.size,
        schemaStatus: LifesumSchemaStatus.duplicateColumns,
      );
    }

    final columnSet = columns.toSet();
    final missingColumns = section.requiredColumns
        .where((required) => !columnSet.contains(required))
        .toList(growable: false);
    return LifesumArchiveEntry(
      section: section,
      compressedSizeBytes: _compressedSizeOf(entry),
      uncompressedSizeBytes: entry.size,
      schemaStatus: missingColumns.isEmpty
          ? LifesumSchemaStatus.ready
          : LifesumSchemaStatus.missingRequiredColumns,
      missingColumns: missingColumns,
    );
  }

  static LifesumExportSection? _sectionForFlatPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.contains('/')) return null;
    final lowerCaseName = normalized.toLowerCase();
    for (final section in LifesumExportSection.values) {
      if (section.fileName == lowerCaseName) return section;
    }
    return null;
  }

  static int _compressedSizeOf(ArchiveFile entry) {
    final rawContent = entry.rawContent;
    return rawContent is ZipFile ? rawContent.compressedSize : entry.size;
  }
}

/// Discards decompressed row data after retaining the first CSV line.
class _HeaderCaptureOutput extends OutputStream {
  _HeaderCaptureOutput(this.maxHeaderSizeBytes, this.maxOutputSizeBytes)
    : super(byteOrder: ByteOrder.littleEndian);

  final int maxHeaderSizeBytes;
  final int maxOutputSizeBytes;
  final List<int> _header = <int>[];
  var _writtenLength = 0;
  var _lineComplete = false;
  var exceededLimit = false;

  Uint8List get headerBytes => Uint8List.fromList(_header);

  @override
  int get length => _writtenLength;

  @override
  void clear() {
    _header.clear();
    _writtenLength = 0;
    _lineComplete = false;
    exceededLimit = false;
  }

  @override
  void flush() {}

  @override
  void writeByte(int value) {
    _writtenLength++;
    if (_writtenLength > maxOutputSizeBytes) {
      throw const _ExpandedEntryTooLarge();
    }
    if (_lineComplete) return;
    if (value == 10 || value == 13) {
      _lineComplete = true;
      return;
    }
    if (_header.length >= maxHeaderSizeBytes) {
      exceededLimit = true;
      return;
    }
    _header.add(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final byteCount = length ?? bytes.length;
    for (var index = 0; index < byteCount; index++) {
      writeByte(bytes[index]);
    }
  }

  @override
  void writeStream(InputStream stream) {
    while (!stream.isEOS) {
      final count = stream.length > 4096 ? 4096 : stream.length;
      writeBytes(stream.readBytes(count).toUint8List());
    }
  }

  @override
  Uint8List subset(int start, [int? end]) {
    final actualEnd = end ?? _header.length;
    return Uint8List.fromList(_header.sublist(start, actualEnd));
  }
}

class _ExpandedEntryTooLarge implements Exception {
  const _ExpandedEntryTooLarge();
}
