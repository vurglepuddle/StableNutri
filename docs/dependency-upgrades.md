# Selected dependency upgrades

September 22, 2026. These versions follow the cached upstream review; this is
not a blanket update to every package's newest release.

## Notifications and timezone

- `flutter_local_notifications` 19.5.0 to 20.1.0: migrate initialization,
  cancellation and scheduling to named arguments. Keep channel IDs, reminder
  IDs, inexact scheduling, permission behavior and delete-all cancellation.
- `flutter_timezone` 3.0.1 to 5.1.0: use `TimezoneInfo.identifier` for the IANA
  lookup, never its localized display name. `timezone` stays at 0.10.1.
- Platform-contract tests exercise the real Android method-channel serializer
  with mocked native responses, including daily recurrence and one-shot fasting.
- Validation at this checkpoint: analyzer clean, 1,273 tests pass, develop debug
  APK builds. Delivery on a phone and iOS compilation remain unverified.

References: [notification migration](https://pub.dev/packages/flutter_local_notifications/versions/20.1.0/changelog),
[timezone API](https://pub.dev/packages/flutter_timezone/versions/5.1.0).

## Sharing

- `share_plus` 10.1.4 to 12.0.2: use `SharePlus.instance.share(ShareParams(...))`.
  Preserve QR image plus text, text fallback, and the button's popover rectangle.
- Android Gradle Plugin moves from 8.11.1 to the package's minimum 8.12.1.
  Existing Gradle 8.14, Kotlin 2.2.20, Java 17 and compile SDK 36 remain.
- Tests await actual QR rasterization and file writing, then inspect the mobile
  plugin payload. They also cover temporary-storage failure and anchor geometry.
- Final validation: analyzer clean, all 1,275 tests pass, develop debug APK builds.
- Native share-sheet interaction on Android/iOS remains a device check.

References: [sharing migration and Android requirements](https://pub.dev/packages/share_plus/versions/12.0.2/changelog),
[Android Gradle Plugin compatibility](https://developer.android.com/build/releases/agp-8-12-0-release-notes).

## Remaining review

Image picker 1.2.3 and compression 2.5.1 are now applied. Existing photo storage,
WebP settings, metadata exclusion and source-file preservation remain intact.
All 1,291 tests pass and the develop debug APK builds; native gallery/camera and
iOS checks remain pending.

Envied and its generator, UUID, JSON annotations,
equatable, and build_runner remain. Preserve the exact ZXing pin; exclude Sentry
and avoid unrelated Supabase changes. Native quick-add widget refinements remain
a separate working-tree change pending phone verification.
