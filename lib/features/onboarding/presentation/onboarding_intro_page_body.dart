import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/sources_screen.dart';
import 'package:opennutritracker/core/presentation/widgets/stable_wordmark.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The welcome page. Stable collects nothing, so there is no policy to
/// accept: a short line says so and Start is always available.
class OnboardingIntroPageBody extends StatelessWidget {
  const OnboardingIntroPageBody({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    return Column(
      children: [
        const StableWordmark(height: 48),
        const SizedBox(height: 32.0),
        Text(
          S.of(context).appDescription,
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32.0),
        Text(
          S.of(context).onboardingIntroDescription,
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8.0),
            Flexible(
              child: Text(
                S.of(context).onboardingNoTrackingLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: palette.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16.0),
        TextButton.icon(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SourcesScreen())),
          icon: const Icon(Icons.menu_book_outlined),
          label: Text(S.of(context).onboardingIntroSourcesLinkLabel),
        ),
      ],
    );
  }
}
