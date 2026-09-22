
# Install dependencies
install:
  flutter pub get

# Generate code (Hive adapters, JSON, mocks)
build:
  dart run build_runner build

# Everyday APK: an optimised release build. Signed with the same debug key as
# every earlier build, so it updates existing installs in place, data intact.
# Output: build/app/outputs/flutter-apk/app-develop-release.apk
apk:
  flutter build apk --release --flavor develop

# Format dart code (excludes lib/generated/ — gitignored gen-l10n output with its own style)
format *OPTIONS:
  dart format {{OPTIONS}} ./lib/core ./lib/features ./lib/l10n ./test

# Generate localizations from lib/l10n/*.arb into lib/generated/ (gitignored)
gen_l10n:
  flutter gen-l10n

# Run tests
test:
  flutter test

# Run CI checks
ci: install (format "--set-exit-if-changed") gen_l10n build && test
  flutter analyze

create_emulator:
  fvm flutter emulators --create --name flutter_emulator

start_emulator:
  fvm flutter emulators --launch flutter_emulator

dev:
  fvm flutter run --flavor develop