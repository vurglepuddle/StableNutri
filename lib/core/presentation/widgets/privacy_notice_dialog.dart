import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Stable's privacy notice: nothing is collected, so there is no policy to
/// link to, only a plain statement of what stays on the device.
Future<void> showPrivacyNoticeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      shape: Dimens.shapeL,
      title: Text(S.of(context).settingsPrivacyNoticeLabel),
      content: Text(S.of(context).privacyNoTelemetryBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context).dialogOKLabel),
        ),
      ],
    ),
  );
}
