import 'package:flutter/material.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openExternalLink(
  BuildContext context,
  Uri uri, {
  LaunchMode mode = LaunchMode.externalApplication,
}) async {
  try {
    if (await launchUrl(uri, mode: mode)) return;
  } catch (_) {
    // Missing browser/store or platform failure should keep the current form.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(S.of(context).linkOpenFailed)));
  }
}
