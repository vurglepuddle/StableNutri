import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_import_preview.dart';

import '../../../../fixture/lifesum_export_fixture.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'stable_lifesum_preview_',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  group('LifesumImportPreview', () {
    test('assembles every selected domain without retaining unknown files', () {
      final zip = writeSanitizedLifesumZip(temporaryDirectory);
      final selection = const LifesumArchiveReader().readCsvSectionsPath(
        zip.path,
        LifesumExportSection.values.toSet(),
      );

      final preview = LifesumImportPreview.fromSelection(selection);

      expect(
        preview.loadedSections,
        unorderedEquals(LifesumExportSection.values),
      );
      expect(preview.unavailableSections, isEmpty);
      expect(preview.inspection.ignoredFileCount, 2);
      expect(preview.food?.candidateCount, 1);
      expect(preview.activity?.candidateCount, 1);
      expect(preview.measurements?.weightCandidateCount, 1);
      expect(preview.measurements?.bodyMeasurementCandidateCount, 1);
      expect(preview.recipes?.candidateCount, 1);
      expect(preview.archiveCandidateCount, 5);
      expect(preview.readyToAddCount, 4);
      expect(preview.existingConflictCount, 0);
      expect(preview.blockingIssueCount, 0);
      expect(preview.warningCount, 0);
      expect(preview.recipeSnapshotPersistenceRequiredCount, 1);
      expect(preview.recipes?.readyToAddCount, 0);
      expect(preview.estimatedWaterCandidateCount, 1);
      expect(preview.estimatedWater?.amountPerDayMl, 2000);
      expect(preview.earliestArchiveCandidateDate, isNotNull);
      expect(preview.latestArchiveCandidateDate, isNotNull);
    });

    test('classifies exact IDs before occupied logical days', () {
      final files = Map<String, String>.of(sanitizedLifesumFiles)
        ..['food.csv'] = _csvWithRows('food.csv', <String>[
          _dataRow('food.csv'),
          _dataRow('food.csv')
              .replaceFirst('2024-01-02', '2024-01-03')
              .replaceFirst('Example oats', 'Example later meal'),
        ])
        ..['exercise.csv'] = _csvWithRows('exercise.csv', <String>[
          _dataRow('exercise.csv'),
          _dataRow('exercise.csv')
              .replaceFirst('2024-01-02', '2024-01-03')
              .replaceFirst('Example walk', 'Example later walk'),
        ]);
      final zip = writeSanitizedLifesumZip(temporaryDirectory, files: files);
      final selection = const LifesumArchiveReader().readCsvSectionsPath(
        zip.path,
        <LifesumExportSection>{
          LifesumExportSection.food,
          LifesumExportSection.exercise,
        },
      );
      const offsetMinutes = 4 * 60 + 30;
      final firstPass = LifesumImportPreview.fromSelection(
        selection,
        dayStartOffsetMinutes: offsetMinutes,
      );
      final foodCandidates = firstPass.food!.parseResult.intakes;
      final activityCandidates = firstPass.activity!.parseResult.activities;

      final preview = LifesumImportPreview.fromSelection(
        selection,
        dayStartOffsetMinutes: offsetMinutes,
        existingIntakes: <IntakeEntity>[
          foodCandidates.first,
          _intakeWith(
            foodCandidates.last,
            id: 'stable-existing-intake',
            dateTime: DateTime(2024, 1, 4, 2),
          ),
        ],
        existingActivities: <UserActivityEntity>[
          activityCandidates.first,
          _activityWith(
            activityCandidates.last,
            id: 'stable-existing-activity',
            date: DateTime(2024, 1, 4, 2),
          ),
        ],
      );

      expect(
        preview.food!.reviews.map((review) => review.conflict),
        <LifesumImportConflict>[
          LifesumImportConflict.exactId,
          LifesumImportConflict.occupiedLogicalDay,
        ],
      );
      expect(preview.food?.candidatesToAdd, isEmpty);
      expect(preview.food?.exactIdConflictCount, 1);
      expect(preview.food?.occupiedDayConflictCount, 1);
      expect(
        preview.activity!.reviews.map((review) => review.conflict),
        <LifesumImportConflict>[
          LifesumImportConflict.exactId,
          LifesumImportConflict.occupiedLogicalDay,
        ],
      );
      expect(preview.activity?.candidatesToAdd, isEmpty);
      expect(preview.existingConflictCount, 4);
      expect(preview.readyToAddCount, 0);
    });

    test('omits unavailable measurement sources without parser errors', () {
      final zip = writeSanitizedLifesumZip(
        temporaryDirectory,
        files: <String, String>{
          'weighins.csv': sanitizedLifesumFiles['weighins.csv']!,
          'README': 'Synthetic test fixture.\n',
        },
      );
      final selection = const LifesumArchiveReader()
          .readCsvSectionsPath(zip.path, <LifesumExportSection>{
            LifesumExportSection.weighIns,
            LifesumExportSection.bodyMeasures,
            LifesumExportSection.bodyFat,
          });

      final preview = LifesumImportPreview.fromSelection(selection);

      expect(preview.loadedSections, {LifesumExportSection.weighIns});
      expect(preview.unavailableSections, <LifesumExportSection>{
        LifesumExportSection.bodyMeasures,
        LifesumExportSection.bodyFat,
      });
      expect(preview.measurements, isNotNull);
      expect(preview.measurements?.weightCandidateCount, 1);
      expect(preview.measurements?.bodyMeasurementCandidateCount, 0);
      expect(preview.measurements?.issues, isEmpty);
      expect(preview.blockingIssueCount, 0);
      expect(preview.archiveCandidateCount, 1);
      expect(preview.readyToAddCount, 1);
      expect(preview.estimatedWater, isNull);
    });

    test(
      'classifies recipe ID and normalized-name conflicts but never applies',
      () {
        final firstRow = _dataRow(
          'recipes.csv',
        ).replaceFirst('Example bowl', 'First bowl');
        final secondRow = _dataRow('recipes.csv')
            .replaceFirst('Example bowl', 'Second bowl')
            .replaceFirst('2024-01-02 12:00:00', '2024-01-04 12:00:00');
        final zip = writeSanitizedLifesumZip(
          temporaryDirectory,
          files: <String, String>{
            'recipes.csv': _csvWithRows('recipes.csv', <String>[
              firstRow,
              secondRow,
            ]),
          },
        );
        final selection = const LifesumArchiveReader().readCsvSectionsPath(
          zip.path,
          <LifesumExportSection>{LifesumExportSection.recipes},
        );
        final firstPass = LifesumImportPreview.fromSelection(selection);
        final recipeCandidates = firstPass.recipes!.parseResult.candidates;

        final preview = LifesumImportPreview.fromSelection(
          selection,
          existingRecipes: <RecipeEntity>[
            _recipe(id: recipeCandidates.first.id, name: 'Different name'),
            _recipe(id: 'stable-recipe', name: '  SECOND   BOWL  '),
          ],
        );

        expect(
          preview.recipes!.reviews.map((review) => review.conflict),
          <LifesumImportConflict>[
            LifesumImportConflict.exactId,
            LifesumImportConflict.normalizedName,
          ],
        );
        expect(preview.recipes?.exactIdConflictCount, 1);
        expect(preview.recipes?.normalizedNameConflictCount, 1);
        expect(preview.recipes?.snapshotPersistenceRequiredCount, 2);
        expect(preview.recipes?.readyToAddCount, 0);
        expect(preview.existingConflictCount, 2);
        expect(preview.readyToAddCount, 0);
      },
    );

    test('keeps existing measurements and estimated-water days untouched', () {
      final zip = writeSanitizedLifesumZip(temporaryDirectory);
      final selection = const LifesumArchiveReader().readCsvSectionsPath(
        zip.path,
        LifesumExportSection.values.toSet(),
      );

      final preview = LifesumImportPreview.fromSelection(
        selection,
        existingWeights: <WeightLogEntity>[
          WeightLogEntity(date: DateTime(2024, 1, 2), weightKg: 75),
        ],
        existingWaterEntries: <WaterIntakeEntity>[
          WaterIntakeEntity(
            id: 'stable-water',
            dateTime: DateTime(2024, 1, 2, 10),
            amountMl: 250,
          ),
        ],
      );

      expect(preview.measurements?.existingWeightConflictCount, 1);
      expect(preview.measurements?.weightsToAdd, isEmpty);
      expect(preview.estimatedWater?.existingDayCount, 1);
      expect(preview.estimatedWaterCandidateCount, 0);
      expect(preview.earliestArchiveCandidateDate, isNotNull);
      expect(preview.latestArchiveCandidateDate, isNotNull);
    });
  });
}

String _dataRow(String fileName) =>
    sanitizedLifesumFiles[fileName]!.trimRight().split('\n').last;

String _csvWithRows(String fileName, List<String> rows) =>
    '${sanitizedLifesumFiles[fileName]!.split('\n').first}\n'
    '${rows.join('\n')}\n';

IntakeEntity _intakeWith(
  IntakeEntity source, {
  required String id,
  required DateTime dateTime,
}) => IntakeEntity(
  id: id,
  unit: source.unit,
  amount: source.amount,
  type: source.type,
  meal: source.meal,
  dateTime: dateTime,
);

UserActivityEntity _activityWith(
  UserActivityEntity source, {
  required String id,
  required DateTime date,
}) => UserActivityEntity(
  id,
  source.duration,
  source.burnedKcal,
  date,
  source.physicalActivityEntity,
  userKcal: source.userKcal,
);

RecipeEntity _recipe({required String id, required String name}) =>
    RecipeEntity(
      id: id,
      name: name,
      description: null,
      ingredients: const [],
      totalWeightG: 1,
      aggregatedNutrimentsPer100: MealNutrimentsEntity.empty(),
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      servingsCount: null,
    );
