import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';

/// A friendly empty state: a soft accent-tinted icon, a title, and optional
/// supporting line. Used where a screen would otherwise show bare text, so an
/// empty diary, search or trends view feels considered rather than blank.
class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool compact;

  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final accent = Theme.of(context).colorScheme.primary;
    final text = Theme.of(context).textTheme;
    final iconSize = compact ? 48.0 : 72.0;
    return Padding(
      padding: EdgeInsets.all(compact ? Dimens.spacing16 : Dimens.spacing32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: compact ? 24 : 32),
          ),
          SizedBox(height: compact ? Dimens.spacing8 : Dimens.spacing16),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: Dimens.spacing8),
            Text(
              subtitle!,
              style: text.bodyMedium?.copyWith(color: palette.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
