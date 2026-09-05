import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/data/repository/water_intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_user_activity_usecase.dart';

void main() {
  test('editing exact calories keeps an imported workout duration', () async {
    final activity = UserActivityEntity(
      'lifesum-activity-example',
      42.5,
      120,
      DateTime(2024, 1, 2),
      PhysicalActivityEntity.customNamed('Example walk'),
      userKcal: 120,
    );
    final repository = _Activities(activity);
    final updated = await UpdateUserActivityUsecase(
      repository,
      _NoUserRead(),
    ).updateUserActivity(activity, 140);
    expect(updated?.duration, 42.5);
    expect(updated?.burnedKcal, 140);
    expect(updated?.userKcal, 140);
    expect(updated?.date, activity.date);
  });

  test(
    'quick water repeats the latest drink across days and ignores estimates',
    () async {
      final entries = [
        WaterIntakeEntity(
          id: 'drink-old',
          dateTime: DateTime(2024, 1, 1),
          amountMl: 250,
        ),
        WaterIntakeEntity(
          id: 'drink-new',
          dateTime: DateTime(2024, 1, 2),
          amountMl: 400,
        ),
        WaterIntakeEntity(
          id: 'lifesum-estimated-water-example',
          dateTime: DateTime(2024, 1, 3),
          amountMl: 2000,
        ),
        WaterIntakeEntity(
          id: 'future',
          dateTime: DateTime(2200),
          amountMl: 600,
        ),
      ];
      expect(
        await GetWaterIntakeUsecase(
          _Water(entries.reversed.toList()),
        ).getQuickAddAmountMl(),
        400,
      );
      expect(
        await GetWaterIntakeUsecase(_Water([])).getQuickAddAmountMl(),
        250,
      );
    },
  );
}

class _NoUserRead extends Fake implements GetUserUsecase {}

class _Activities extends Fake implements UserActivityRepository {
  _Activities(this.activity);
  final UserActivityEntity activity;
  @override
  Future<UserActivityEntity?> updateUserActivity(
    String id,
    double newDuration,
    double newBurnedKcal, {
    double? userKcal,
  }) async => UserActivityEntity(
    id,
    newDuration,
    newBurnedKcal,
    activity.date,
    activity.physicalActivityEntity,
    userKcal: userKcal,
  );
}

class _Water extends Fake implements WaterIntakeRepository {
  _Water(this.entries);
  final List<WaterIntakeEntity> entries;
  @override
  Future<List<WaterIntakeEntity>> getAllEntries() async => entries;
}
