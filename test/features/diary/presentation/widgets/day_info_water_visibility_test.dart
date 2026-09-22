import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_profiles_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/diary/presentation/widgets/day_info_widget.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/meal_detail/presentation/bloc/meal_detail_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

class _MealDetailBloc extends Fake implements MealDetailBloc {}

class _HomeBloc extends Fake implements HomeBloc {}

class _Profiles extends Fake implements GetProfilesUsecase {
  final _profile = ProfileEntity(
    id: 'p1',
    name: 'Me',
    createdAt: DateTime(2026),
    boxSuffix: '',
  );

  @override
  List<ProfileEntity> getProfiles() => [_profile];

  @override
  String get activeProfileId => _profile.id;

  @override
  ProfileEntity? getActiveProfile() => _profile;
}

/// Show Water Tracking off hides the day's water history in Diary, the same
/// way Show Activity Tracking hides its Activity section.
void main() {
  setUpAll(() {
    final locator = GetIt.instance;
    locator.registerFactory<MealDetailBloc>(_MealDetailBloc.new);
    locator.registerFactory<HomeBloc>(_HomeBloc.new);
    locator.registerFactory<GetProfilesUsecase>(_Profiles.new);
  });

  tearDownAll(GetIt.instance.reset);

  Future<void> pumpDay(
    WidgetTester tester, {
    required bool showWaterTracking,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<EnergyUnitProvider>(
        create: (_) => EnergyUnitProvider(),
        child: MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          // Diary lists the day's sections; the scroll view stands in for it.
          home: Scaffold(
            body: SingleChildScrollView(
              child: DayInfoWidget(
                selectedDay: DateTime(2026, 9, 22),
                trackedDayEntity: null,
                userActivities: const [],
                breakfastIntake: const [],
                lunchIntake: const [],
                dinnerIntake: const [],
                snackIntake: const [],
                usesImperialUnits: false,
                showActivityTracking: false,
                showWaterTracking: showWaterTracking,
                onDeleteIntake: (_, _) {},
                onDeleteActivity: (_, _) {},
                onCopyIntake: (_, _, _) {},
                onCopyActivity: (_, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the water section shows by default', (tester) async {
    await pumpDay(tester, showWaterTracking: true);
    expect(find.byKey(const Key('diary-water')), findsOneWidget);
  });

  testWidgets('turning water tracking off hides the section', (tester) async {
    await pumpDay(tester, showWaterTracking: false);
    expect(find.byKey(const Key('diary-water')), findsNothing);
  });
}
