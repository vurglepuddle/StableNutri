import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/delete_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_activity_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_water_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_intake_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/update_user_activity_usecase.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';

import '../../../../fixture/user_entity_fixtures.dart';

class _Config extends Fake implements GetConfigUsecase {
  @override
  Future<ConfigEntity> getConfig() async =>
      const ConfigEntity(true, true, false, AppThemeEntity.light);
}

class _Intakes extends Fake implements GetIntakeUsecase {
  @override
  Future<List<IntakeEntity>> getTodayBreakfastIntake({
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => [];

  @override
  Future<List<IntakeEntity>> getTodayLunchIntake({
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => [];

  @override
  Future<List<IntakeEntity>> getTodayDinnerIntake({
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => [];

  @override
  Future<List<IntakeEntity>> getTodaySnackIntake({
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => [];
}

class _Activities extends Fake implements GetUserActivityUsecase {
  @override
  Future<List<UserActivityEntity>> getTodayUserActivity({
    int dayStartOffsetHours = 0,
    int dayStartOffsetMinutes = 0,
  }) async => [];
}

class _User extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async =>
      UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight;
}

class _KcalGoal extends Fake implements GetKcalGoalUsecase {
  @override
  Future<double> getKcalGoal({
    UserEntity? userEntity,
    double? totalKcalActivitiesParam,
    double? kcalUserAdjustment,
  }) async => 2000;
}

class _MacroGoal extends Fake implements GetMacroGoalUsecase {
  @override
  Future<double> getCarbsGoal(double totalCalorieGoal) async => 250;

  @override
  Future<double> getFatsGoal(double totalCalorieGoal) async => 60;

  @override
  Future<double> getProteinsGoal(double totalCalorieGoal) async => 100;
}

/// One in-memory list behind both the read and write water use cases.
class _Water {
  final entries = <WaterIntakeEntity>[];
}

class _GetWater extends Fake implements GetWaterIntakeUsecase {
  _GetWater(this.water);

  final _Water water;

  @override
  Future<List<WaterIntakeEntity>> getTodayEntries({
    required int dayStartOffsetTotalMinutes,
  }) async => List.of(water.entries);

  @override
  Future<int> getQuickAddAmountMl() async => 250;
}

class _AddWater extends Fake implements AddWaterIntakeUsecase {
  _AddWater(this.water);

  final _Water water;

  @override
  Future<void> addEntry(WaterIntakeEntity entry) async =>
      water.entries.add(entry);
}

class _AddConfig extends Fake implements AddConfigUsecase {}

class _DeleteIntake extends Fake implements DeleteIntakeUsecase {}

class _UpdateIntake extends Fake implements UpdateIntakeUsecase {}

class _DeleteActivity extends Fake implements DeleteUserActivityUsecase {}

class _TrackedDay extends Fake implements AddTrackedDayUsecase {}

class _UpdateActivity extends Fake implements UpdateUserActivityUsecase {}

class _DeleteWater extends Fake implements DeleteWaterIntakeUsecase {}

void main() {
  late HomeBloc bloc;
  late List<HomeState> states;
  late StreamSubscription<HomeState> subscription;

  setUp(() async {
    final water = _Water();
    bloc = HomeBloc(
      _Config(),
      _AddConfig(),
      _Intakes(),
      _DeleteIntake(),
      _UpdateIntake(),
      _Activities(),
      _DeleteActivity(),
      _TrackedDay(),
      _KcalGoal(),
      _MacroGoal(),
      _UpdateActivity(),
      _User(),
      _GetWater(water),
      _AddWater(water),
      _DeleteWater(),
    );
    states = [];
    subscription = bloc.stream.listen(states.add);
    bloc.add(const LoadItemsEvent());
    await bloc.stream.firstWhere((state) => state is HomeLoadedState);
    states.clear();
  });

  tearDown(() async {
    await subscription.cancel();
    await bloc.close();
  });

  Future<HomeLoadedState> nextLoaded() async =>
      await bloc.stream.firstWhere((state) => state is HomeLoadedState)
          as HomeLoadedState;

  test(
    'a water pour refreshes a loaded dashboard without the spinner',
    () async {
      final loaded = nextLoaded();
      await bloc.addWaterIntake(250);

      expect((await loaded).waterMlToday, 250);
      // A loading state would unmount the water card, so the poured cup
      // would appear already full instead of animating.
      expect(states.whereType<HomeLoadingState>(), isEmpty);
    },
  );

  test('a reset reload hides the previous dashboard first', () async {
    final loaded = nextLoaded();
    bloc.add(const LoadItemsEvent(reset: true));
    await loaded;

    expect(states.first, isA<HomeLoadingState>());
  });
}
