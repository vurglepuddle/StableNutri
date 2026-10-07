import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/data/dbo/profile_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/dbo/weight_log_dbo.dart';
import 'package:opennutritracker/core/data/dbo/body_measurement_log_dbo.dart';
import 'package:opennutritracker/core/data/dbo/water_intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/fasting_session_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_gender_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_pal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/user_weight_goal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/calories_profile_dbo.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_dbo.dart';
import 'package:opennutritracker/core/data/data_source/custom_activity_template_dbo.dart';

abstract final class BackupCodec {
  static Future<void> writeRows(
    String base,
    Box<dynamic> box,
    Map<dynamic, dynamic> rows,
  ) => switch (base) {
    'ConfigBox' => box.putAll(rows.cast<dynamic, ConfigDBO>()),
    'AppConfigBox' => box.putAll(rows.cast<dynamic, ConfigDBO>()),
    'CustomMealBox' => box.putAll(rows.cast<dynamic, MealDBO>()),
    'RecipeBox' => box.putAll(rows.cast<dynamic, RecipeDBO>()),
    'IntakeBox' => box.putAll(rows.cast<dynamic, IntakeDBO>()),
    'TrackedDayBox' => box.putAll(rows.cast<dynamic, TrackedDayDBO>()),
    'WeightLogBox' => box.putAll(rows.cast<dynamic, WeightLogDBO>()),
    'BodyMeasurementLogBox' => box.putAll(
      rows.cast<dynamic, BodyMeasurementLogDBO>(),
    ),
    'WaterIntakeBox' => box.putAll(rows.cast<dynamic, WaterIntakeDBO>()),
    'FastingBox' => box.putAll(rows.cast<dynamic, FastingSessionDBO>()),
    'CustomActivityTemplateBox' => box.putAll(
      rows.cast<dynamic, CustomActivityTemplateDBO>(),
    ),
    'UserActivityBox' => box.putAll(rows.cast<dynamic, UserActivityDBO>()),
    'ProfileBox' => box.putAll(rows.cast<dynamic, ProfileDBO>()),
    'UserBox' => box.putAll(rows.cast<dynamic, UserDBO>()),
    'CycleBox' => box.putAll(rows.cast<dynamic, String>()),
    'DailyStepsBox' => box.putAll(rows.cast<dynamic, String>()),
    'LifesumImportJournalBox' => box.putAll(rows.cast<dynamic, String>()),
    _ => throw const FormatException('Unknown store'),
  };

  static Object encode(String base, dynamic value) {
    if (value is String) return value;
    if (value is ProfileDBO) {
      return {
        'id': value.id,
        'name': value.name,
        'createdAt': value.createdAt.toIso8601String(),
        'boxSuffix': value.boxSuffix,
        'imagePath': value.imagePath,
      };
    }
    if (value is UserDBO) {
      return {
        'birthday': value.birthday.toIso8601String(),
        'heightCM': value.heightCM,
        'weightKG': value.weightKG,
        'gender': value.gender.name,
        'goal': value.goal.name,
        'pal': value.pal.name,
        'weeklyWeightGoalKg': value.weeklyWeightGoalKg,
        'caloriesProfile': value.caloriesProfile?.name,
        'targetWeightKg': value.targetWeightKg,
        'caloriesTaperEnabled': value.caloriesTaperEnabled,
      };
    }
    return value.toJson() as Object;
  }

  static Object decode(String base, Object value) {
    if ([
      HiveDBProvider.dailyStepsBoxName,
      HiveDBProvider.lifesumImportJournalBoxName,
      HiveDBProvider.cycleBoxName,
    ].contains(base)) {
      return value as String;
    }
    final j = Map<String, dynamic>.from(value as Map);
    return switch (base) {
      HiveDBProvider.profileBoxName => ProfileDBO(
        id: j['id'] as String,
        name: j['name'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        boxSuffix: j['boxSuffix'] as String,
        imagePath: j['imagePath'] as String?,
      ),
      HiveDBProvider.userBoxName => UserDBO(
        birthday: DateTime.parse(j['birthday'] as String),
        heightCM: (j['heightCM'] as num).toDouble(),
        weightKG: (j['weightKG'] as num).toDouble(),
        gender: UserGenderDBO.values.byName(j['gender'] as String),
        goal: UserWeightGoalDBO.values.byName(j['goal'] as String),
        pal: UserPALDBO.values.byName(j['pal'] as String),
        weeklyWeightGoalKg: (j['weeklyWeightGoalKg'] as num?)?.toDouble(),
        caloriesProfile: j['caloriesProfile'] == null
            ? null
            : CaloriesProfileDBO.values.byName(j['caloriesProfile'] as String),
        targetWeightKg: (j['targetWeightKg'] as num?)?.toDouble(),
        caloriesTaperEnabled: j['caloriesTaperEnabled'] as bool,
      ),
      'ConfigBox' => ConfigDBO.fromJson(j),
      'AppConfigBox' => ConfigDBO.fromJson(j),
      'CustomMealBox' => MealDBO.fromJson(j),
      'RecipeBox' => RecipeDBO.fromJson(j),
      'IntakeBox' => IntakeDBO.fromJson(j),
      'TrackedDayBox' => TrackedDayDBO.fromJson(j),
      'WeightLogBox' => WeightLogDBO.fromJson(j),
      'BodyMeasurementLogBox' => BodyMeasurementLogDBO.fromJson(j),
      'WaterIntakeBox' => WaterIntakeDBO.fromJson(j),
      'FastingBox' => FastingSessionDBO.fromJson(j),
      'CustomActivityTemplateBox' => CustomActivityTemplateDBO.fromJson(j),
      'UserActivityBox' => UserActivityDBO.fromJson(j),
      _ => throw const FormatException('Unknown backup store'),
    };
  }
}
