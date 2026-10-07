# October 7 implementation checkpoint

Branch `feat/stable-next` continues `stable` at `183e7239`. Changes are split
into local commits. No push, phone installation or remote CI run was performed.
The IDE-facing TODO, design plan and handoff in `../Design/` are outside Git;
this checkpoint preserves the implementation summary inside the repository.

- Cached photo providers retain identity and synchronous keys across updates.
  Drag placeholders match the real card; delete-target exits no longer end drag.
- Saved OFF/FDC corrections enter Library and take priority on the next scan.
  Snapshot-only edits continue to affect only the selected diary entry.
- The calorie bar has compact rounded display text and a small filled fire icon.
  All calculations and stored nutrition retain their original precision.
- The central Add FAB is removed. Today retains a small toolbar Add action.
  Navigation is Today / Trends / Library / optional Cycle / You.
- Cycle is off by default for any profile. It supports setup estimates, actual
  start/end dates, backfill, gap exclusions, forecast corrections, an optional
  three-day reminder, actual/forecast Diary markers, and history in Trends.
  Actual records remain separate from predictions; no phase/fertility model.
- Full backup includes every profile, settings, logs, Library and referenced local
  photos. Restore validates then stages a separate encrypted dataset, activating
  it on restart. See [format and transfer guide](export-format.md).
- Weekly nutrients use seven logical diary days. Missing information is unknown;
  partial totals are labelled and averages require complete nutrient data.
- Search hides equivalent custom-food copies without deleting stored records.
  Barcode products and foods with different micronutrients remain separate.
- Scanner supports additional GS1 matrix/QR forms and explains unsupported
  decoded codes. Camera focus/decoding reliability still requires phone checks.
- Stable CI checks pushes and PRs using the pinned SDK. Selected dependency
  updates are recorded in [dependency notes](dependency-upgrades.md).
- Failed links show feedback, displayed macro shares total 100%, and an import
  screen regression checks chronological date-range rendering.

Validation: Flutter 3.44.8 / Dart 3.12.2; generation and formatting pass;
static analysis is clean; all **1,438 tests pass**. A develop release APK was
built at `build/app/outputs/flutter-apk/app-develop-release.apk` (88,836,201 bytes).
Tests use synthetic data, including complete multi-profile backup round trips,
failed staging, archive corruption, photo rebuilds and large-text layouts.

Remaining: acceptance of the new release on a phone, native backup picker and
restart/transfer, Cycle reminder delivery, matrix camera reliability, first
GitHub CI execution, broader translation/cleanup work and platform edge cases.
Onboarding verification, circle redesign, dashboard reordering and custom icons
remain deferred. Rescue-toggle placement and external Cycle-import format await
user decisions; the accepted daily-use profile must not be reset for tests.
