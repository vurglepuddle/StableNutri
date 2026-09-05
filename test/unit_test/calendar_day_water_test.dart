import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/repository/water_intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/tracked_day_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_user_activity_usecase.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';

class _Config implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async => const ConfigEntity(
    false,
    false,
    false,
    AppThemeEntity.system,
    dayStartOffsetHours: 4,
    dayStartOffsetMinutes: 30,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Intakes implements GetIntakeUsecase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<List<IntakeEntity>>.value([]);
}

class _Activities implements GetUserActivityUsecase {
  @override
  Future<List<UserActivityEntity>> getUserActivityByDay(
    DateTime day, {
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TrackedDays implements GetTrackedDayUsecase {
  @override
  Future<TrackedDayEntity?> getTrackedDay(DateTime day) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Any accidental write in this inspection flow fails the test.
class _Writes
    implements
        DeleteIntakeUsecase,
        DeleteUserActivityUsecase,
        AddTrackedDayUsecase,
        UpdateIntakeUsecase,
        UpdateUserActivityUsecase,
        AddConfigUsecase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected write: ${invocation.memberName}');
}

class _WaterRepository implements WaterIntakeRepository {
  final List<WaterIntakeEntity> entries;
  final ranges = <(DateTime, DateTime)>[];
  _WaterRepository(this.entries);
  @override
  Future<List<WaterIntakeEntity>> getEntriesInRange(
    DateTime from,
    DateTime to,
  ) async {
    ranges.add((from, to));
    return entries
        .where(
          (entry) =>
              !entry.dateTime.isBefore(from) && entry.dateTime.isBefore(to),
        )
        .toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected water operation');
}

void main() {
  test(
    'Archive loads water even without food, using the selected logical day',
    () async {
      final water = _WaterRepository([
        WaterIntakeEntity(
          id: 'before',
          dateTime: DateTime(2024, 2, 1, 4, 29),
          amountMl: 100,
        ),
        WaterIntakeEntity(
          id: 'lifesum-estimated-water-example',
          dateTime: DateTime(2024, 2, 1, 4, 30),
          amountMl: 2000,
        ),
        WaterIntakeEntity(
          id: 'late',
          dateTime: DateTime(2024, 2, 2, 4, 29),
          amountMl: 350,
        ),
        WaterIntakeEntity(
          id: 'next-day',
          dateTime: DateTime(2024, 2, 2, 4, 30),
          amountMl: 250,
        ),
      ]);
      final writes = _Writes();
      final bloc = CalendarDayBloc(
        _Activities(),
        _Intakes(),
        writes,
        writes,
        _TrackedDays(),
        writes,
        writes,
        writes,
        _Config(),
        writes,
        GetWaterIntakeUsecase(water),
      );
      addTearDown(bloc.close);
      Future<CalendarDayLoaded> load(DateTime day) async {
        final loaded = bloc.stream.firstWhere(
          (state) => state is CalendarDayLoaded,
        );
        bloc.add(LoadCalendarDayEvent(day));
        return await loaded as CalendarDayLoaded;
      }

      final first = await load(DateTime(2024, 2, 1, 13));
      expect(first.trackedDayEntity, isNull);
      expect(first.waterEntries.map((entry) => entry.id), [
        'lifesum-estimated-water-example',
        'late',
      ]);
      expect(
        first.waterEntries.fold(0, (sum, entry) => sum + entry.amountMl),
        2350,
      );
      expect(water.ranges.single, (
        DateTime(2024, 2, 1, 4, 30),
        DateTime(2024, 2, 2, 4, 30),
      ));
      final next = await load(DateTime(2024, 2, 2));
      expect(next.waterEntries.single.id, 'next-day');
      final empty = await load(DateTime(2024, 2, 3));
      expect(empty.waterEntries, isEmpty);
      expect(water.entries, hasLength(4));
    },
  );
}
