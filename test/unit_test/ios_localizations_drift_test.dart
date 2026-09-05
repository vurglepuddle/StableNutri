import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against `ios/Runner/Info.plist`'s `CFBundleLocalizations` falling
/// out of sync with `lib/l10n/intl_*.arb`. iOS uses that array to decide
/// which languages to surface in Settings → app language picker; if a locale
/// is missing here, iOS users can't pick it even though Flutter ships the
/// strings. (The pre-existing miss caused 6 locales to be invisible on iOS.)
void main() {
  test(
    'Info.plist CFBundleLocalizations contains every intl_*.arb locale',
    () async {
      final l10nDir = Directory('lib/l10n');
      expect(
        l10nDir.existsSync(),
        isTrue,
        reason: 'expected to find lib/l10n directory',
      );

      final arbLocales = l10nDir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((name) => name.startsWith('intl_') && name.endsWith('.arb'))
          .map(
            (name) =>
                name.substring('intl_'.length, name.length - '.arb'.length),
          )
          .toSet();

      expect(
        arbLocales,
        isNotEmpty,
        reason: 'sanity check: at least one ARB file should exist',
      );
      expect(
        arbLocales,
        contains('en'),
        reason: 'the source ARB intl_en.arb must always exist',
      );

      final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
      final localizationsBlock = RegExp(
        r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(infoPlist);
      expect(
        localizationsBlock,
        isNotNull,
        reason: 'Info.plist must declare CFBundleLocalizations',
      );

      final declaredLocales = RegExp(r'<string>([a-zA-Z-]+)</string>')
          .allMatches(localizationsBlock!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      final missing = arbLocales.difference(declaredLocales);
      expect(
        missing,
        isEmpty,
        reason:
            'CFBundleLocalizations is missing the following locales that '
            'are shipped via intl_*.arb files: ${missing.join(', ')}. '
            'Add each missing <string>code</string> entry to '
            'ios/Runner/Info.plist.',
      );
    },
  );
}
