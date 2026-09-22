import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';

/// First-run calculation using the same functions as the dashboard. There
/// are no logged activities or manual adjustments on a new profile.
class OnboardingCalorieBreakdown {
  final double maintenanceKcal;
  final double adjustmentKcal;
  final double totalKcal;

  OnboardingCalorieBreakdown.fromUser(UserEntity user)
    : maintenanceKcal = CalorieGoalCalc.getTdee(user),
      adjustmentKcal = CalorieGoalCalc.getKcalGoalAdjustment(
        user.goal,
        weeklyWeightGoalKg: user.weeklyWeightGoalKg,
      ),
      totalKcal = CalorieGoalCalc.getTotalKcalGoal(user, 0);
}
