import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

/// Give interactive rows their own ink surface above the card decoration.
class CycleCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const CycleCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) => AppCard(
    child: Material(
      color: Colors.transparent,
      borderRadius: Dimens.borderRadiusL,
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    ),
  );
}
