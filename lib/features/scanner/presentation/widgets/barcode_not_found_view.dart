import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Shown when a scan decodes cleanly but the code resolves to nothing —
/// neither a saved custom meal, nor the local cache, nor Open Food Facts.
///
/// This is a dead end only if we make it one. The code itself is good
/// information: the user is holding the product, so they are in the best
/// possible position to either name the food themselves or point at the item
/// they already keep for it. Both onward paths are offered here, with the
/// scanned digits shown so a misread is obvious before either is taken.
class BarcodeNotFoundView extends StatelessWidget {
  final String barcode;
  final VoidCallback onConnectExistingPressed;
  final VoidCallback onCreateItemPressed;
  final VoidCallback onScanAgainPressed;

  const BarcodeNotFoundView({
    super.key,
    required this.barcode,
    required this.onConnectExistingPressed,
    required this.onCreateItemPressed,
    required this.onScanAgainPressed,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Dimens.spacing24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Dimens.spacing24),
            Icon(
              Icons.qr_code_scanner_rounded,
              size: 64,
              color: palette.textMuted,
            ),
            const SizedBox(height: Dimens.spacing20),
            Text(
              s.scannerNotFoundTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: palette.textStrong,
              ),
            ),
            const SizedBox(height: Dimens.spacing12),
            // The digits get their own tile in a monospace face: this is the
            // one moment where the exact characters matter, and a misread
            // (an 8 for a 6, a dropped leading zero) is far easier to catch
            // when the glyphs line up than inside a run of prose.
            AppCard(
              color: palette.surfaceMuted,
              padding: const EdgeInsets.symmetric(
                horizontal: Dimens.spacing16,
                vertical: Dimens.spacing12,
              ),
              child: Text(
                barcode,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontFamilyFallback: const ['Courier'],
                  letterSpacing: 1.5,
                  color: palette.textStrong,
                ),
              ),
            ),
            const SizedBox(height: Dimens.spacing12),
            Text(
              s.scannerNotFoundMessage(barcode),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: Dimens.spacing24),
            // Creating the item is the primary action: it is the one that
            // ends with the food logged *and* saved for next time, and it is
            // the likelier of the two for a product the database has never
            // heard of.
            Semantics(
              identifier: 'scanner-not-found-create',
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: Dimens.shapeM,
                  padding: const EdgeInsets.symmetric(
                    vertical: Dimens.spacing16,
                  ),
                ),
                onPressed: onCreateItemPressed,
                icon: const Icon(Icons.add_rounded),
                label: Text(s.scannerCreateItemLabel),
              ),
            ),
            const SizedBox(height: Dimens.spacing12),
            Semantics(
              identifier: 'scanner-not-found-connect',
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  shape: Dimens.shapeM,
                  side: BorderSide(
                    color: palette.border,
                    width: Dimens.hairline,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: Dimens.spacing16,
                  ),
                ),
                onPressed: onConnectExistingPressed,
                icon: const Icon(Icons.link_rounded),
                label: Text(s.scannerConnectExistingLabel),
              ),
            ),
            const SizedBox(height: Dimens.spacing8),
            Semantics(
              identifier: 'scanner-not-found-scan-again',
              child: TextButton.icon(
                onPressed: onScanAgainPressed,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(s.scannerScanAgainLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
