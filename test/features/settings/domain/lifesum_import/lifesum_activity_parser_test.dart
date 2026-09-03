import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/features/settings/domain/lifesum_import/lifesum_activity_parser.dart';

import '../../../../fixture/lifesum_export_fixture.dart';

void main() {
  group('LifesumActivityParser', () {
    test('maps Lifesum rows to exact custom activity snapshots', () {
      final result = LifesumActivityParser.parse(
        sanitizedLifesumFiles['exercise.csv']!,
      );

      expect(result.sourceRowCount, 1);
      expect(result.candidates, hasLength(1));
      expect(result.issues, isEmpty);
      final activity = result.activities.single;
      expect(activity.duration, 30);
      expect(activity.burnedKcal, 120);
      expect(activity.userKcal, 120);
      expect(activity.effectiveBurnedKcal, 120);
      expect(activity.physicalActivityEntity.isCustom, isTrue);
      expect(activity.physicalActivityEntity.specificActivity, 'Example walk');
      expect(activity.id, startsWith('lifesum-activity-'));
      expect(activity.id, isNot(contains('Example')));
    });

    test('reports zero-calorie Health Connect step mirrors as ignored', () {
      final result = LifesumActivityParser.parse(
        _csvWithRows(<String>[
          '2024-01-02,Walking,source-specific duration,0,Health Connect',
        ]),
      );

      expect(result.candidates, isEmpty);
      expect(result.ignoredHealthConnectCount, 1);
      expect(
        result.issues.single.code,
        LifesumActivityIssueCode.healthConnectMirrorIgnored,
      );
    });

    test('does not silently ignore unexpected Health Connect calories', () {
      final result = LifesumActivityParser.parse(
        _csvWithRows(<String>['2024-01-02,Walking,45,100,Health Connect']),
      );

      expect(result.candidates, isEmpty);
      expect(result.ignoredHealthConnectCount, 0);
      expect(
        result.issues.single.code,
        LifesumActivityIssueCode.unexpectedHealthConnectCalories,
      );
    });

    test('preserves repeated Lifesum rows with deterministic IDs', () {
      const row = '2024-01-02,Example activity,20,80,Lifesum';
      final csv = _csvWithRows(<String>[row, row]);

      final first = LifesumActivityParser.parse(csv);
      final second = LifesumActivityParser.parse(csv);

      expect(first.candidates, hasLength(2));
      expect(first.activities[0].id, endsWith('-001'));
      expect(first.activities[1].id, endsWith('-002'));
      expect(first.activities[0].id, second.activities[0].id);
      expect(first.activities[1].id, second.activities[1].id);
    });

    test('reconstructs sorted activity totals by day', () {
      final result = LifesumActivityParser.parse(
        _csvWithRows(<String>[
          '2024-01-03,Example one,30,120,Lifesum',
          '2024-01-02,Example two,20,80,Lifesum',
          '2024-01-02,Example three,10,40,Lifesum',
        ]),
      );

      expect(result.trackedDays, hasLength(2));
      final firstDay = result.trackedDays.first;
      expect(firstDay.day, DateTime(2024, 1, 2));
      expect(firstDay.activityCount, 2);
      expect(firstDay.durationMinutes, 30);
      expect(firstDay.caloriesBurned, 120);
    });

    test('places date-only rows inside a custom logical day', () {
      const offset = 20 * 60 + 30;
      final result = LifesumActivityParser.parse(
        sanitizedLifesumFiles['exercise.csv']!,
        dayStartOffsetMinutes: offset,
      );

      final timestamp = result.activities.single.date;
      expect(timestamp, DateTime(2024, 1, 3, 8, 30, 0, 0, 2));
      expect(
        DayBoundaryCalc.logicalDayOfMinutes(timestamp, offset),
        DateTime(2024, 1, 2),
      );
    });

    test('skips invalid source values with value-free row issues', () {
      final result = LifesumActivityParser.parse(
        _csvWithRows(<String>[
          '2024-02-30,Example,30,100,Lifesum',
          '2024-01-02,,30,100,Lifesum',
          '2024-01-02,Example,NaN,100,Lifesum',
          '2024-01-02,Example,-1,100,Lifesum',
          '2024-01-02,Example,30,0,Lifesum',
          '2024-01-02,Example,30,100,Unknown',
        ]),
      );

      expect(result.candidates, isEmpty);
      expect(result.warningCount, 6);
      expect(result.issues.every((issue) => issue.rowNumber != null), isTrue);
    });

    test('missing required headers block the exercise section', () {
      final result = LifesumActivityParser.parse(
        'date,title\n2024-01-02,Example',
      );

      expect(result.candidates, isEmpty);
      expect(result.blockingIssueCount, greaterThan(0));
      expect(result.issues.every((issue) => issue.rowNumber == null), isTrue);
    });
  });
}

String _csvWithRows(List<String> rows) =>
    '${sanitizedLifesumFiles['exercise.csv']!.split('\n').first}\n'
    '${rows.join('\n')}\n';
