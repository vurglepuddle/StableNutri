import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/body_measurement_log_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/recipe_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_archive_reader.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_existing_history_loader.dart';

import '../../../../fixture/lifesum_export_fixture.dart';

void main() {
  group('LifesumExistingHistoryLoader', () {
    test(
      'starts every read together and returns immutable profile data',
      () async {
        final gate = Completer<void>();
        var startedReads = 0;

        Future<List<T>> loadAfterGate<T>() {
          startedReads++;
          return gate.future.then((_) => <T>[]);
        }

        final loader = LifesumExistingHistoryLoader(
          activeProfileId: () => 'profile-a',
          activeProfileGeneration: () => 1,
          loadIntakes: loadAfterGate<IntakeEntity>,
          loadActivities: loadAfterGate<UserActivityEntity>,
          loadWeights: loadAfterGate<WeightLogEntity>,
          loadBodyMeasurements: loadAfterGate<BodyMeasurementLogEntity>,
          loadTrackedDays: loadAfterGate<TrackedDayEntity>,
          loadWaterEntries: loadAfterGate<WaterIntakeEntity>,
          loadRecipes: loadAfterGate<RecipeEntity>,
        );

        final loading = loader.load();
        await Future<void>.delayed(Duration.zero);
        expect(startedReads, 7);
        gate.complete();
        final history = await loading;

        expect(history.profileId, 'profile-a');
        expect(history.intakes, isEmpty);
        expect(history.intakes.clear, throwsUnsupportedError);
      },
    );

    test('rejects a snapshot spanning a switch away and back', () async {
      final gate = Completer<void>();
      var activeProfileId = 'profile-a';
      var activeProfileGeneration = 1;

      Future<List<T>> loadAfterGate<T>() => gate.future.then((_) => <T>[]);

      final loader = LifesumExistingHistoryLoader(
        activeProfileId: () => activeProfileId,
        activeProfileGeneration: () => activeProfileGeneration,
        loadIntakes: loadAfterGate<IntakeEntity>,
        loadActivities: loadAfterGate<UserActivityEntity>,
        loadWeights: loadAfterGate<WeightLogEntity>,
        loadBodyMeasurements: loadAfterGate<BodyMeasurementLogEntity>,
        loadTrackedDays: loadAfterGate<TrackedDayEntity>,
        loadWaterEntries: loadAfterGate<WaterIntakeEntity>,
        loadRecipes: loadAfterGate<RecipeEntity>,
      );

      final loading = loader.load();
      activeProfileId = 'profile-b';
      activeProfileGeneration++;
      activeProfileId = 'profile-a';
      activeProfileGeneration++;
      gate.complete();

      await expectLater(
        loading,
        throwsA(
          isA<LifesumExistingHistoryException>().having(
            (exception) => exception.failure,
            'failure',
            LifesumExistingHistoryFailure.activeProfileChanged,
          ),
        ),
      );
    });
  });

  test(
    'history snapshot feeds tracked-day and water conflicts into preview',
    () {
      final temporaryDirectory = Directory.systemTemp.createTempSync(
        'stable_lifesum_history_preview_',
      );
      addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
      final zip = writeSanitizedLifesumZip(temporaryDirectory);
      final selection = const LifesumArchiveReader().readCsvSectionsPath(
        zip.path,
        LifesumExportSection.values.toSet(),
      );
      final history = LifesumExistingHistory(
        profileId: 'profile-a',
        intakes: const <IntakeEntity>[],
        activities: const <UserActivityEntity>[],
        weights: const <WeightLogEntity>[],
        bodyMeasurements: const <BodyMeasurementLogEntity>[],
        trackedDays: <TrackedDayEntity>[
          TrackedDayEntity(
            day: DateTime(2024, 1, 2),
            calorieGoal: 1800,
            caloriesTracked: 100,
          ),
        ],
        waterEntries: <WaterIntakeEntity>[
          WaterIntakeEntity(
            id: 'stable-water',
            dateTime: DateTime(2024, 1, 2, 10),
            amountMl: 250,
          ),
        ],
        recipes: const <RecipeEntity>[],
      );

      final preview = history.buildPreview(selection);

      expect(preview.food?.occupiedDayConflictCount, 1);
      expect(preview.activity?.occupiedDayConflictCount, 1);
      expect(preview.estimatedWater?.existingDayCount, 1);
      expect(preview.estimatedWaterCandidateCount, 0);
      expect(preview.measurements?.readyToAddCount, 2);
    },
  );
}
