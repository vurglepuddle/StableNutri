import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/calories_profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';

/// #32: the home water chip seeds its goal from the user's gender (and,
/// for non-binary users, their CaloriesProfileEntity) when the config
/// has no override stored yet. Numbers are derived from EFSA 2010 total
/// water AI minus the ~20% food-moisture share — see ConfigEntity
/// docstring for the full citation chain.
void main() {
  group('ConfigEntity.seedWaterGoalForGender', () {
    test('female users seed at 1500 ml (EFSA-derived)', () {
      expect(
        ConfigEntity.seedWaterGoalForGender(UserGenderEntity.female),
        1500,
      );
    });

    test('male users seed at 1900 ml (EFSA-derived)', () {
      expect(ConfigEntity.seedWaterGoalForGender(UserGenderEntity.male), 1900);
    });

    test('non-binary users default to the averaged midpoint (1700 ml)', () {
      expect(
        ConfigEntity.seedWaterGoalForGender(UserGenderEntity.nonBinary),
        1700,
      );
    });

    test('non-binary users with estrogen profile seed at the female value', () {
      expect(
        ConfigEntity.seedWaterGoalForGender(
          UserGenderEntity.nonBinary,
          caloriesProfile: CaloriesProfileEntity.estrogenTypical,
        ),
        1500,
      );
    });

    test(
      'non-binary users with testosterone profile seed at the male value',
      () {
        expect(
          ConfigEntity.seedWaterGoalForGender(
            UserGenderEntity.nonBinary,
            caloriesProfile: CaloriesProfileEntity.testosteroneTypical,
          ),
          1900,
        );
      },
    );
  });

  group('ConfigEntity.effectiveDailyWaterGoalMl', () {
    test('returns the user override when one is stored', () {
      const config = ConfigEntity(
        false,
        false,
        false,
        AppThemeEntity.system,
        dailyWaterGoalMl: 2400,
      );
      expect(config.effectiveDailyWaterGoalMl(UserGenderEntity.female), 2400);
    });

    test('falls back to the gendered seed when no override is stored', () {
      const config = ConfigEntity(false, false, false, AppThemeEntity.system);
      expect(config.effectiveDailyWaterGoalMl(UserGenderEntity.male), 1900);
      expect(config.effectiveDailyWaterGoalMl(UserGenderEntity.female), 1500);
    });
  });
}
