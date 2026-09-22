import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/info_dialog.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// A small (?) beside the product link that opens the Open Food Facts data
/// notice, instead of the full paragraph under every product.
class OffDisclaimer extends StatelessWidget {
  const OffDisclaimer({super.key});

  static const _source = 'Open Food Facts';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return IconButton(
      tooltip: _source,
      icon: Icon(
        Icons.help_outline_rounded,
        size: 20,
        color: palette.textMuted,
      ),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) =>
            InfoDialog(title: _source, body: S.of(context).offDisclaimer),
      ),
    );
  }
}
