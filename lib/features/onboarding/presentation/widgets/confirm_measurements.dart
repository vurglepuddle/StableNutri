import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/body_weight_unit_entity.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_display_format.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Typo prompts, not additional hard bounds. Explicit Keep is required before
/// leaving the measurement page; cancelling or Change keeps the page open.
Future<bool> confirmOnboardingMeasurements(
  BuildContext context, {
  required double heightCm,
  required double weightKg,
  required double? targetWeightKg,
  required bool imperialHeight,
  required BodyWeightUnit weightUnit,
  required Set<(String, double)> confirmed,
}) async {
  final s = S.of(context);
  final checks = <(String, double, String)>[];
  if (heightCm < 120 || heightCm > 230) {
    final display = formatHeight(
      heightCm,
      imperialHeight,
      cmLabel: s.cmLabel,
      ftLabel: s.ftLabel,
      inLabel: s.inLabel,
    );
    checks.add((
      'height',
      heightCm,
      s.onboardingImplausibleHeightBody(display),
    ));
  }
  String weight(double kg) => formatBodyWeight(
    kg,
    weightUnit,
    kgLabel: s.kgLabel,
    lbLabel: s.lbsLabel,
    stLabel: s.stLabel,
  );
  if (weightKg < 30 || weightKg > 300) {
    checks.add((
      'weight',
      weightKg,
      s.onboardingImplausibleWeightBody(weight(weightKg)),
    ));
  }
  if (targetWeightKg != null && (targetWeightKg < 30 || targetWeightKg > 300)) {
    checks.add((
      'target',
      targetWeightKg,
      s.onboardingImplausibleTargetBody(weight(targetWeightKg)),
    ));
  }
  for (final (field, value, message) in checks) {
    if (confirmed.contains((field, value))) continue;
    if (!context.mounted) return false;
    final keep = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.onboardingImplausibleTitle),
        content: Text(message),
        actions: [
          Semantics(
            identifier: 'onboarding-implausible-change',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(s.onboardingImplausibleChange),
            ),
          ),
          Semantics(
            identifier: 'onboarding-implausible-keep',
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(s.onboardingImplausibleKeep),
            ),
          ),
        ],
      ),
    );
    if (keep != true || !context.mounted) return false;
    confirmed.add((field, value));
  }
  return context.mounted;
}
