import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_type_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_nutriments_dbo.dart';
import 'package:opennutritracker/core/data/dbo/physical_activity_dbo.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';

import '../helpers/fake_hive_db_provider.dart';
import '../helpers/hive_test_setup.dart';

/// A configured day-start offset was being subtracted from the calendar day
/// the user tapped as well as from the stored entries. Subtracting six hours
/// from a midnight day label lands in the previous day, so with a 06:00
/// boundary, selecting the 20th listed the 19th's food and activities.
///
/// The two meanings are separate: a day *label* names a column and stays
/// put; only a real timestamp is resolved through the boundary.
///
/// These reads only disagree with the wall-clock date between midnight and
/// the boundary, so a test that reads the real clock passes for most of the
/// day whether the code is right or wrong. DayBoundaryCalc.clock is pinned
/// here and restored afterwards.
void main() {
  const sixAm = 6 * 60;

  group('DayBoundaryCalc.isMomentInLogicalDayMinutes', () {
    test('the selected day keeps its own entries', () {
      final label = DateTime(2026, 1, 20);

      // Logged on the 20th at noon: squarely inside the 20th's logical day.
      expect(
        DayBoundaryCalc.isMomentInLogicalDayMinutes(
          label,
          DateTime(2026, 1, 20, 12, 0),
          sixAm,
        ),
        isTrue,
      );
    });

    test('the previous day stays on the previous day', () {
      final label = DateTime(2026, 1, 20);

      expect(
        DayBoundaryCalc.isMomentInLogicalDayMinutes(
          label,
          DateTime(2026, 1, 19, 12, 0),
          sixAm,
        ),
        isFalse,
      );
    });

    test('a small-hours entry belongs to the day before it', () {
      // 03:00 on the 21st is still the 20th under a 06:00 boundary.
      expect(
        DayBoundaryCalc.isMomentInLogicalDayMinutes(
          DateTime(2026, 1, 20),
          DateTime(2026, 1, 21, 3, 0),
          sixAm,
        ),
        isTrue,
      );
      expect(
        DayBoundaryCalc.isMomentInLogicalDayMinutes(
          DateTime(2026, 1, 21),
          DateTime(2026, 1, 21, 3, 0),
          sixAm,
        ),
        isFalse,
      );
    });

    // Entries added from the diary carry the calendar cell itself as their
    // timestamp, and JsonMealImporter dates a date-only entry at local
    // midnight. Rolling those back would file every one of them a day early.
    test('a stored day label is matched verbatim, not rolled back', () {
      expect(
        DayBoundaryCalc.isMomentInLogicalDayMinutes(
          DateTime(2026, 1, 20),
          DateTime(2026, 1, 20),
          sixAm,
        ),
        isTrue,
      );
      expect(
        DayBoundaryCalc.isMomentInLogicalDayMinutes(
          DateTime(2026, 1, 20),
          DateTime.utc(2026, 1, 20),
          sixAm,
        ),
        isTrue,
      );
    });

    test('at a zero offset it is plain calendar-day equality', () {
      expect(
        DayBoundaryCalc.isMomentInLogicalDayMinutes(
          DateTime(2026, 1, 20),
          DateTime(2026, 1, 20, 2, 0),
          0,
        ),
        isTrue,
      );
      expect(
        DayBoundaryCalc.isMomentInLogicalDayMinutes(
          DateTime(2026, 1, 20),
          DateTime(2026, 1, 21, 2, 0),
          0,
        ),
        isFalse,
      );
    });
  });

  group('currentLogicalDayLabel', () {
    tearDown(() => DayBoundaryCalc.clock = DateTime.now);

    test('before the boundary, today is still yesterday', () {
      DayBoundaryCalc.clock = () => DateTime(2026, 1, 21, 2, 30);

      expect(
        DayBoundaryCalc.currentLogicalDayLabel(6, 0),
        DateTime(2026, 1, 20),
      );
    });

    test('after the boundary, today is today', () {
      DayBoundaryCalc.clock = () => DateTime(2026, 1, 21, 7, 30);

      expect(
        DayBoundaryCalc.currentLogicalDayLabel(6, 0),
        DateTime(2026, 1, 21),
      );
    });

    test('a stored minute outside 0-59 cannot inflate the offset', () {
      expect(DayBoundaryCalc.totalMinutesOf(6, 90), 6 * 60 + 59);
      expect(DayBoundaryCalc.totalMinutesOf(6, -5), 6 * 60);
    });
  });

  group('the diary reads, through the real data sources', () {
    late Box<IntakeDBO> intakeBox;
    late Box<UserActivityDBO> activityBox;
    late IntakeDataSource intakes;
    late UserActivityDataSource activities;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      Hive.init('.');
      registerHiveAdaptersOnce();

      intakeBox = await Hive.openBox<IntakeDBO>('offset_intake');
      activityBox = await Hive.openBox<UserActivityDBO>('offset_activity');
      final provider = FakeHiveDBProvider(
        intakeBox: intakeBox,
        userActivityBox: activityBox,
      );
      intakes = IntakeDataSource(provider);
      activities = UserActivityDataSource(provider);
    });

    tearDown(() async {
      DayBoundaryCalc.clock = DateTime.now;
      await Hive.deleteFromDisk();
    });

    test('selecting a day lists that day, not the one before it', () async {
      await intakeBox.addAll([
        _intake('nineteenth', DateTime(2026, 1, 19, 12, 0)),
        _intake('twentieth', DateTime(2026, 1, 20, 12, 0)),
      ]);

      final result = await intakes.getAllIntakesByDate(
        IntakeTypeDBO.lunch,
        DateTime(2026, 1, 20),
        dayStartOffsetHours: 6,
      );

      expect(
        result.map((i) => i.id),
        ['twentieth'],
        reason:
            'the offset was applied to the tapped day as well as to the '
            'entries, so the selection slid back a day',
      );
    });

    test('a small-hours entry lists under the previous day', () async {
      await intakeBox.addAll([
        _intake('late-night', DateTime(2026, 1, 21, 3, 0)),
      ]);

      final twentieth = await intakes.getAllIntakesByDate(
        IntakeTypeDBO.lunch,
        DateTime(2026, 1, 20),
        dayStartOffsetHours: 6,
      );
      final twentyFirst = await intakes.getAllIntakesByDate(
        IntakeTypeDBO.lunch,
        DateTime(2026, 1, 21),
        dayStartOffsetHours: 6,
      );

      expect(twentieth.map((i) => i.id), ['late-night']);
      expect(twentyFirst, isEmpty);
    });

    test(
      'an entry added from the diary stays on the day it was filed under',
      () async {
        // The diary stamps the calendar cell itself as the timestamp.
        await intakeBox.addAll([
          _intake('added-from-diary', DateTime.utc(2026, 1, 20)),
        ]);

        final result = await intakes.getAllIntakesByDate(
          IntakeTypeDBO.lunch,
          DateTime(2026, 1, 20),
          dayStartOffsetHours: 6,
        );

        expect(result.map((i) => i.id), ['added-from-diary']);
      },
    );

    test('activities follow the same rule', () async {
      await activityBox.addAll([
        _activity('nineteenth', DateTime(2026, 1, 19, 12, 0)),
        _activity('twentieth', DateTime(2026, 1, 20, 12, 0)),
      ]);

      final result = await activities.getAllUserActivitiesByDate(
        DateTime(2026, 1, 20),
        dayStartOffsetHours: 6,
      );

      expect(result.map((a) => a.id), ['twentieth']);
    });

    // The mirror-image half. getTodayLunchIntake used to hand a raw
    // DateTime.now() to a query that takes a day label, which asks for the
    // wall-clock date — so between midnight and the boundary, Home listed
    // the new calendar day while the diary listed the logical one.
    test('"today" before the boundary means the previous label', () async {
      await intakeBox.addAll([
        _intake('twentieth', DateTime(2026, 1, 20, 20, 0)),
        _intake('twenty-first', DateTime(2026, 1, 21, 12, 0)),
      ]);
      // 02:30 on the 21st, with a 06:00 boundary: still the 20th.
      DayBoundaryCalc.clock = () => DateTime(2026, 1, 21, 2, 30);

      final usecase = GetIntakeUsecase(IntakeRepository(intakes));
      final result = await usecase.getTodayLunchIntake(dayStartOffsetHours: 6);

      expect(
        result.map((i) => i.id),
        ['twentieth'],
        reason:
            'Home asked for the wall-clock date instead of the logical '
            'day, so it disagreed with the diary until 06:00',
      );
    });

    test('"today" after the boundary means the current label', () async {
      await intakeBox.addAll([
        _intake('twentieth', DateTime(2026, 1, 20, 20, 0)),
        _intake('twenty-first', DateTime(2026, 1, 21, 12, 0)),
      ]);
      DayBoundaryCalc.clock = () => DateTime(2026, 1, 21, 7, 30);

      final usecase = GetIntakeUsecase(IntakeRepository(intakes));
      final result = await usecase.getTodayLunchIntake(dayStartOffsetHours: 6);

      expect(result.map((i) => i.id), ['twenty-first']);
    });

    test('a zero offset is unchanged by any of this', () async {
      await intakeBox.addAll([
        _intake('nineteenth', DateTime(2026, 1, 19, 12, 0)),
        _intake('twentieth', DateTime(2026, 1, 20, 12, 0)),
        _intake('small-hours', DateTime(2026, 1, 20, 3, 0)),
      ]);

      final result = await intakes.getAllIntakesByDate(
        IntakeTypeDBO.lunch,
        DateTime(2026, 1, 20),
      );

      expect(result.map((i) => i.id), ['twentieth', 'small-hours']);
    });
  });
}

IntakeDBO _intake(String id, DateTime when) => IntakeDBO(
  id: id,
  unit: 'g',
  amount: 100,
  type: IntakeTypeDBO.lunch,
  meal: MealDBO(
    code: null,
    name: id,
    brands: null,
    thumbnailImageUrl: null,
    mainImageUrl: null,
    url: null,
    mealQuantity: '100',
    mealUnit: 'g',
    servingQuantity: null,
    servingUnit: null,
    servingSize: null,
    source: MealSourceDBO.custom,
    nutriments: MealNutrimentsDBO(
      energyKcal100: 100,
      carbohydrates100: null,
      fat100: null,
      proteins100: null,
      sugars100: null,
      saturatedFat100: null,
      fiber100: null,
    ),
  ),
  dateTime: when,
);

UserActivityDBO _activity(String id, DateTime when) => UserActivityDBO(
  id,
  30.0,
  200.0,
  when,
  PhysicalActivityDBO(
    'running_general',
    'running, general',
    'running, general',
    8.0,
    const [],
    PhysicalActivityTypeDBO.running,
  ),
);
