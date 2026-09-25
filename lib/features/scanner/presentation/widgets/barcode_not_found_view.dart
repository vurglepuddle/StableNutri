import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/calc/unit_calc.dart';
import 'package:opennutritracker/core/utils/off_const.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/scanner/data/metro_data_source.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Shown when a scan decodes cleanly but the code resolves to nothing —
/// neither a saved custom meal, nor the local cache, nor Open Food Facts,
/// nor METRO — or only to a product without its nutrition values.
///
/// This is a dead end only if we make it one. The code itself is good
/// information: the user is holding the product, so they are in the best
/// possible position to either name the food themselves or point at the item
/// they already keep for it. Both onward paths are offered here, with the
/// scanned digits shown so a misread is obvious before either is taken.
/// When METRO has products that may be this one, they come first, for the
/// user to pick from; nothing is picked for them.
class BarcodeNotFoundView extends StatelessWidget {
  final String barcode;
  final VoidCallback onConnectExistingPressed;
  final VoidCallback onCreateItemPressed;
  final VoidCallback onScanAgainPressed;

  /// What the product is called, shown so the user knows the scan read the
  /// right package; it also seeds the new food's name.
  final String? suggestedName;

  /// True while that name is still being looked up.
  final bool isLookingUpName;

  /// The product without (all of) its nutrition, when a source has it. It
  /// changes the heading, and names where [suggestedName] came from.
  final MealEntity? partial;

  /// True while METRO is being searched for [metroMatches].
  final bool isSearchingMetro;

  final List<MealEntity> metroMatches;
  final ValueChanged<MealEntity>? onMetroMatchPressed;

  /// Energy in kJ rather than kcal, as the user chose in Settings.
  final bool usesKilojoules;

  const BarcodeNotFoundView({
    super.key,
    required this.barcode,
    required this.onConnectExistingPressed,
    required this.onCreateItemPressed,
    required this.onScanAgainPressed,
    this.suggestedName,
    this.isLookingUpName = false,
    this.partial,
    this.isSearchingMetro = false,
    this.metroMatches = const [],
    this.onMetroMatchPressed,
    this.usesKilojoules = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final known = partial;

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
              known == null ? s.scannerNotFoundTitle : s.scannerIncompleteTitle,
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
            if (isLookingUpName) ...[
              const SizedBox(height: Dimens.spacing12),
              _Pending(text: s.scannerNameLookupPending, palette: palette),
            ],
            if (suggestedName != null) ...[
              const SizedBox(height: Dimens.spacing12),
              Semantics(
                identifier: 'scanner-not-found-suggested-name',
                child: AppCard(
                  color: palette.surfaceMuted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Dimens.spacing16,
                    vertical: Dimens.spacing12,
                  ),
                  child: Column(
                    children: [
                      Text(
                        suggestedName!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: palette.textStrong,
                        ),
                      ),
                      const SizedBox(height: Dimens.spacing4),
                      Text(
                        known == null
                            ? s.scannerSuggestedNameSource
                            : s.scannerPartialSource(sourceNameOf(known)),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: Dimens.spacing12),
            Text(
              known == null
                  ? s.scannerNotFoundMessage(barcode)
                  : s.scannerIncompleteMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textMuted,
              ),
            ),
            if (isSearchingMetro) ...[
              const SizedBox(height: Dimens.spacing16),
              _Pending(text: s.scannerMetroSearching, palette: palette),
            ],
            if (metroMatches.isNotEmpty) ...[
              const SizedBox(height: Dimens.spacing24),
              Text(
                s.scannerMetroMatchesTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: palette.textStrong,
                ),
              ),
              const SizedBox(height: Dimens.spacing4),
              Text(
                s.scannerMetroMatchesHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: Dimens.spacing12),
              for (final (index, match) in metroMatches.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: Dimens.spacing8),
                  child: Semantics(
                    identifier: 'scanner-not-found-metro-match-$index',
                    child: _MetroMatchCard(
                      match: match,
                      usesKilojoules: usesKilojoules,
                      palette: palette,
                      onPressed: onMetroMatchPressed == null
                          ? null
                          : () => onMetroMatchPressed!(match),
                    ),
                  ),
                ),
            ],
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

/// The database a food came from, as the user knows it.
String sourceNameOf(MealEntity meal) =>
    meal.backendSource == MetroDataSource.sourceCode
    ? MetroDataSource.displayName
    : OFFConst.offSourceName;

class _Pending extends StatelessWidget {
  final String text;
  final AppPalette palette;

  const _Pending({required this.text, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(width: Dimens.spacing8),
        Flexible(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
          ),
        ),
      ],
    );
  }
}

/// One METRO product the scan may be: photo, name, pack size and its
/// values per 100 g, so two sizes of the same line can be told apart.
class _MetroMatchCard extends StatelessWidget {
  final MealEntity match;
  final bool usesKilojoules;
  final AppPalette palette;
  final VoidCallback? onPressed;

  const _MetroMatchCard({
    required this.match,
    required this.usesKilojoules,
    required this.palette,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final image = match.thumbnailImageUrl;
    return AppCard(
      color: palette.surface,
      onTap: onPressed,
      padding: const EdgeInsets.all(Dimens.spacing12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Dimens.radiusS / 2),
            child: SizedBox.square(
              dimension: 48,
              child: image == null
                  ? Icon(Icons.fastfood_outlined, color: palette.textMuted)
                  : CachedNetworkImage(
                      imageUrl: image,
                      fit: BoxFit.contain,
                      errorWidget: (_, _, _) => Icon(
                        Icons.fastfood_outlined,
                        color: palette.textMuted,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: Dimens.spacing12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.name ?? '',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: palette.textStrong,
                  ),
                ),
                const SizedBox(height: Dimens.spacing4),
                Text(
                  _details(s),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: palette.textMuted),
        ],
      ),
    );
  }

  String _details(S s) {
    final n = match.nutriments;
    final unit = match.mealUnit == 'ml' ? s.milliliterUnit : s.gramUnit;
    final kcal = n.energyKcal100;
    final parts = [
      if (match.mealQuantity != null) '${match.mealQuantity} $unit',
      if (kcal != null)
        usesKilojoules
            ? '${_number(UnitCalc.kcalToKj(kcal))} ${s.kjLabel}'
            : '${_number(kcal)} ${s.kcalLabel}',
      if (n.proteins100 != null)
        '${s.proteinLabel} ${_number(n.proteins100!)} ${s.gramUnit}',
      if (n.fat100 != null) '${s.fatLabel} ${_number(n.fat100!)} ${s.gramUnit}',
      if (n.carbohydrates100 != null)
        '${s.carbsLabel} ${_number(n.carbohydrates100!)} ${s.gramUnit}',
    ];
    if (kcal == null &&
        n.proteins100 == null &&
        n.fat100 == null &&
        n.carbohydrates100 == null) {
      parts.add(s.scannerMetroNoNutrition);
    }
    return parts.join(' · ');
  }

  static String _number(double value) {
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toString();
  }
}
