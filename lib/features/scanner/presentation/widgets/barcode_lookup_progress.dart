import 'dart:async';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/features/scanner/domain/usecase/search_product_by_barcode_usecase.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The wait between a scan and its result. A bare spinner reads as a hang
/// once a lookup crosses several slow databases, so it says which one it is
/// asking, and after [slowAfter] that it is still at it.
class BarcodeLookupProgress extends StatefulWidget {
  static const slowAfter = Duration(seconds: 5);

  final BarcodeLookupStage stage;

  const BarcodeLookupProgress({super.key, required this.stage});

  @override
  State<BarcodeLookupProgress> createState() => _BarcodeLookupProgressState();
}

class _BarcodeLookupProgressState extends State<BarcodeLookupProgress> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(BarcodeLookupProgress.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final text = switch (widget.stage) {
      BarcodeLookupStage.local => s.scannerLookupStarting,
      BarcodeLookupStage.openFoodFacts => s.scannerLookupOpenFoodFacts,
      BarcodeLookupStage.metro => s.scannerLookupMetro,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Dimens.spacing24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: Dimens.spacing20),
            Semantics(
              liveRegion: true,
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: palette.textStrong,
                ),
              ),
            ),
            if (_slow) ...[
              const SizedBox(height: Dimens.spacing8),
              Semantics(
                liveRegion: true,
                child: Text(
                  s.scannerLookupSlow,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
