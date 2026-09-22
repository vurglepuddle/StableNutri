import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/add_user_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_user_usecase.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../fixture/user_entity_fixtures.dart';

/// Each load returns a config that differs from the last, so every refresh
/// produces a new loaded state to wait for.
class _Config extends Fake implements GetConfigUsecase {
  var showWater = true;

  @override
  Future<ConfigEntity> getConfig() async {
    showWater = !showWater;
    return ConfigEntity(
      true,
      true,
      false,
      AppThemeEntity.light,
      showWaterTracking: showWater,
    );
  }
}

class _User extends Fake implements GetUserUsecase {
  @override
  Future<UserEntity> getUserData() async =>
      UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight;
}

class _Cache extends Fake implements RemoteSearchCacheDataSource {
  @override
  int get count => 0;

  @override
  Future<int> getStorageSizeBytes() async => 0;
}

class _AddConfig extends Fake implements AddConfigUsecase {}

class _AddTrackedDay extends Fake implements AddTrackedDayUsecase {}

class _KcalGoal extends Fake implements GetKcalGoalUsecase {}

class _MacroGoal extends Fake implements GetMacroGoalUsecase {}

class _TrackedDay extends Fake implements GetTrackedDayUsecase {}

class _AddUser extends Fake implements AddUserUsecase {}

/// Settings is embedded in You. A refresh that swapped either for its
/// spinner collapsed the page and scrolled it away from the switch the user
/// had just changed. Only a profile switch hides the loaded content.
void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'Stable',
      packageName: 'com.example.stable',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  /// States emitted by [load] after [bloc] has loaded once.
  Future<List<S>> refreshStates<S, L extends S>(
    BlocBase<S> bloc,
    void Function() load,
  ) async {
    load();
    await bloc.stream.firstWhere((state) => state is L);
    final states = <S>[];
    final subscription = bloc.stream.listen(states.add);
    load();
    await bloc.stream.firstWhere((state) => state is L);
    await subscription.cancel();
    return states;
  }

  group('Settings', () {
    SettingsBloc settings() => SettingsBloc(
      _Config(),
      _AddConfig(),
      _AddTrackedDay(),
      _KcalGoal(),
      _MacroGoal(),
      _Cache(),
      _TrackedDay(),
    );

    test('a refresh keeps the loaded settings on screen', () async {
      final bloc = settings();
      addTearDown(bloc.close);
      final states = await refreshStates<SettingsState, SettingsLoadedState>(
        bloc,
        () => bloc.add(const LoadSettingsEvent()),
      );
      expect(states.whereType<SettingsLoadingState>(), isEmpty);
      expect(states.single, isA<SettingsLoadedState>());
    });

    test('a profile switch hides the old settings first', () async {
      final bloc = settings();
      addTearDown(bloc.close);
      bloc.add(const LoadSettingsEvent());
      await bloc.stream.firstWhere((state) => state is SettingsLoadedState);
      final next = bloc.stream.take(2).toList();
      bloc.add(const LoadSettingsEvent(reset: true));
      expect((await next).first, isA<SettingsLoadingState>());
    });
  });

  group('You', () {
    ProfileBloc profile() => ProfileBloc(
      _User(),
      _AddUser(),
      _AddTrackedDay(),
      _Config(),
      _KcalGoal(),
    );

    test('a refresh keeps the loaded page on screen', () async {
      final bloc = profile();
      addTearDown(bloc.close);
      final states = await refreshStates<ProfileState, ProfileLoadedState>(
        bloc,
        () => bloc.add(LoadProfileEvent()),
      );
      expect(states.whereType<ProfileLoadingState>(), isEmpty);
      expect(states.single, isA<ProfileLoadedState>());
    });

    test('a profile switch hides the old profile first', () async {
      final bloc = profile();
      addTearDown(bloc.close);
      bloc.add(LoadProfileEvent());
      await bloc.stream.firstWhere((state) => state is ProfileLoadedState);
      final next = bloc.stream.take(2).toList();
      bloc.add(LoadProfileEvent(reset: true));
      expect((await next).first, isA<ProfileLoadingState>());
    });
  });
}
