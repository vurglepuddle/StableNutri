import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/sources_screen.dart';
import 'package:opennutritracker/core/presentation/widgets/privacy_notice_dialog.dart';
import 'package:opennutritracker/core/presentation/widgets/stable_wordmark.dart';
import 'package:opennutritracker/generated/l10n.dart';

class OnboardingIntroPageBody extends StatefulWidget {
  const OnboardingIntroPageBody({
    super.key,
    required this.setPageContent,
    this.initialAcceptedPolicy = false,
    this.initialAcceptedDataCollection = false,
  });

  final Function(bool active, bool acceptedDataCollection) setPageContent;
  final bool initialAcceptedPolicy;
  final bool initialAcceptedDataCollection;

  @override
  State<OnboardingIntroPageBody> createState() =>
      _OnboardingIntroPageBodyState();
}

class _OnboardingIntroPageBodyState extends State<OnboardingIntroPageBody> {
  late bool _acceptedPolicy = widget.initialAcceptedPolicy;
  late final bool _acceptedDataCollection =
      widget.initialAcceptedDataCollection;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const StableWordmark(height: 48),
        const SizedBox(height: 32.0),
        Text(
          S.of(context).appDescription,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32.0),
        Text(
          S.of(context).onboardingIntroDescription,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16.0),
        ListTile(
          onTap: () => _togglePolicy(),
          title: Text.rich(
            textAlign: TextAlign.center,
            TextSpan(
              text: S.of(context).readLabel,
              style: Theme.of(context).textTheme.bodySmall,
              children: [
                TextSpan(
                  text: ' ${S.of(context).settingsPrivacyNoticeLabel}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => showPrivacyNoticeDialog(context),
                ),
              ],
            ),
          ),
          leading: Semantics(
            identifier: 'onboarding-checkbox-privacy',
            child: Checkbox(
              value: _acceptedPolicy,
              onChanged: (value) {
                if (value != null) {
                  _togglePolicy();
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 8.0),
        TextButton.icon(
          onPressed: () => _openSources(context),
          icon: const Icon(Icons.menu_book_outlined),
          label: Text(S.of(context).onboardingIntroSourcesLinkLabel),
        ),
      ],
    );
  }

  void _togglePolicy() {
    setState(() {
      _acceptedPolicy = !_acceptedPolicy;
      widget.setPageContent(_acceptedPolicy, _acceptedDataCollection);
    });
  }

  void _openSources(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SourcesScreen()));
  }
}
