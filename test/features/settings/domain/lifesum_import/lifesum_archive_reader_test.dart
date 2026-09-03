import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';

import '../../../../fixture/lifesum_export_fixture.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'stable_lifesum_reader_',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  group('LifesumArchiveReader', () {
    test('recognizes supported schemas and aggregates ignored files', () {
      final zip = writeSanitizedLifesumZip(temporaryDirectory);

      final inspection = const LifesumArchiveReader().inspectPath(zip.path);

      expect(inspection.fileCount, sanitizedLifesumFiles.length);
      expect(inspection.directoryCount, 0);
      expect(inspection.recognizedEntries, hasLength(6));
      expect(
        inspection.importableSections,
        unorderedEquals(LifesumExportSection.values),
      );
      expect(inspection.missingSections, isEmpty);
      expect(inspection.duplicateSections, isEmpty);
      expect(inspection.ignoredFileCount, 2);
      expect(inspection.ignoredUncompressedSizeBytes, greaterThan(0));
      expect(inspection.archiveSizeBytes, zip.lengthSync());
      expect(
        inspection.recognizedEntries.every(
          (entry) =>
              entry.compressedSizeBytes > 0 && entry.uncompressedSizeBytes > 0,
        ),
        isTrue,
      );
    });

    test('reports required columns missing from a known file', () {
      final files = Map<String, String>.of(sanitizedLifesumFiles)
        ..['weighins.csv'] =
            'date,height_cm,goal_weight_kg\n2024-01-02,170,68\n';
      final zip = writeSanitizedLifesumZip(temporaryDirectory, files: files);

      final inspection = const LifesumArchiveReader().inspectPath(zip.path);
      final weighIns = inspection.recognizedEntries.singleWhere(
        (entry) => entry.section == LifesumExportSection.weighIns,
      );

      expect(weighIns.schemaStatus, LifesumSchemaStatus.missingRequiredColumns);
      expect(weighIns.missingColumns, ['weight_kg']);
      expect(
        inspection.importableSections,
        isNot(contains(LifesumExportSection.weighIns)),
      );
    });

    test('does not recognize a supported filename inside a directory', () {
      final zip = writeSanitizedLifesumZip(
        temporaryDirectory,
        files: <String, String>{
          'nested/food.csv': sanitizedLifesumFiles['food.csv']!,
          'README': 'Synthetic test fixture.\n',
        },
      );

      final inspection = const LifesumArchiveReader().inspectPath(zip.path);

      expect(inspection.recognizedEntries, isEmpty);
      expect(inspection.ignoredFileCount, 2);
      expect(inspection.missingSections, contains(LifesumExportSection.food));
    });

    test('makes case-insensitive duplicate sections non-importable', () {
      final zip = writeSanitizedLifesumZip(
        temporaryDirectory,
        files: <String, String>{
          'food.csv': sanitizedLifesumFiles['food.csv']!,
          'FOOD.CSV': sanitizedLifesumFiles['food.csv']!,
        },
      );

      final inspection = const LifesumArchiveReader().inspectPath(zip.path);

      expect(inspection.recognizedEntries, hasLength(2));
      expect(inspection.duplicateSections, {LifesumExportSection.food});
      expect(
        inspection.importableSections,
        isNot(contains(LifesumExportSection.food)),
      );
    });

    test('rejects archives outside configured safety limits', () {
      final zip = writeSanitizedLifesumZip(temporaryDirectory);
      const reader = LifesumArchiveReader(maxEntries: 1);

      expect(
        () => reader.inspectPath(zip.path),
        throwsA(
          isA<LifesumArchiveReadException>().having(
            (error) => error.failure,
            'failure',
            LifesumArchiveFailure.tooManyEntries,
          ),
        ),
      );
    });

    test('closes the archive file after inspection', () {
      final zip = writeSanitizedLifesumZip(temporaryDirectory);

      const LifesumArchiveReader().inspectPath(zip.path);

      expect(() => zip.deleteSync(), returnsNormally);
    });

    test('loads only requested schema-valid CSV sections', () {
      final zip = writeSanitizedLifesumZip(temporaryDirectory);

      final selection = const LifesumArchiveReader().readCsvSectionsPath(
        zip.path,
        <LifesumExportSection>{
          LifesumExportSection.food,
          LifesumExportSection.exercise,
        },
      );

      expect(
        selection.loadedSections,
        unorderedEquals(<LifesumExportSection>{
          LifesumExportSection.food,
          LifesumExportSection.exercise,
        }),
      );
      expect(selection.unavailableSections, isEmpty);
      expect(
        selection[LifesumExportSection.food],
        sanitizedLifesumFiles['food.csv'],
      );
      expect(
        selection[LifesumExportSection.exercise],
        sanitizedLifesumFiles['exercise.csv'],
      );
      expect(selection[LifesumExportSection.recipes], isNull);
    });

    test('reports requested sections with invalid schemas as unavailable', () {
      final files = Map<String, String>.of(sanitizedLifesumFiles)
        ..['weighins.csv'] =
            'date,height_cm,goal_weight_kg\n2024-01-02,170,68\n';
      final zip = writeSanitizedLifesumZip(temporaryDirectory, files: files);

      final selection = const LifesumArchiveReader().readCsvSectionsPath(
        zip.path,
        <LifesumExportSection>{
          LifesumExportSection.food,
          LifesumExportSection.weighIns,
        },
      );

      expect(selection.loadedSections, {LifesumExportSection.food});
      expect(selection.unavailableSections, {LifesumExportSection.weighIns});
    });

    test('enforces an aggregate selected-content memory limit', () {
      final zip = writeSanitizedLifesumZip(temporaryDirectory);
      const reader = LifesumArchiveReader(maxSelectedUncompressedSizeBytes: 8);

      expect(
        () => reader.readCsvSectionsPath(zip.path, <LifesumExportSection>{
          LifesumExportSection.food,
        }),
        throwsA(
          isA<LifesumArchiveReadException>().having(
            (error) => error.failure,
            'failure',
            LifesumArchiveFailure.selectedContentTooLarge,
          ),
        ),
      );
    });

    test('closes the archive file after reading selected content', () {
      final zip = writeSanitizedLifesumZip(temporaryDirectory);

      const LifesumArchiveReader().readCsvSectionsPath(
        zip.path,
        <LifesumExportSection>{LifesumExportSection.food},
      );

      expect(() => zip.deleteSync(), returnsNormally);
    });
  });
}
