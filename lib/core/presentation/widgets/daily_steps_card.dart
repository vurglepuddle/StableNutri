import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/domain/entity/daily_steps.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Walking progress has its own unit. It never masquerades as burned calories.
class DailyStepsCard extends StatelessWidget {
  final DailySteps total;
  const DailyStepsCard({super.key, required this.total});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.directions_walk_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.healthConnectWalkingSteps(
                      NumberFormat.decimalPattern().format(total.steps),
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    s.healthConnectUpdatedAt(
                      DateFormat.MMMd().add_Hm().format(total.readAt),
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
