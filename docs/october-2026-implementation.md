# October implementation checkpoint

## October 9: food entry and compact Cycle averages

- Food Quick Add also offers kcal/kJ entry independent of profile preference.
  Unit switches preserve exact energy behind rounded text; saved diary and
  tracked-day totals use kcal and normal display follows the profile unit.
  The follow-up passes 28 focused checks plus analyzer/format/diff checks,
  including all input/preference combinations and large-text layouts. The
  1,477-test full-suite result below predates this Quick Add follow-up. Release
  APK rebuilt with the Quick Add selector in all packaged libraries; not installed.
- Selecting a remote food for logging keeps a lasting per-profile Library
  snapshot, with full OFF nutrition/servings fetched when available. Offline
  failures retain the selected nutrition; saved corrections and labels survive.
  Library snapshots are already included in full backup. Photos retain their
  existing image-cache behavior, separate from saved nutrition.
- Search displays local matches before online lookup finishes. The combined
  All list deduplicates products across its source lists.
- Slot Recent prioritizes that slot's last 14 logical diary days, including
  the selected day, then global recents. Priority precedes food deduplication;
  older/future logs receive no special priority. Diary history stays untouched.
- The food form offers a kcal/kJ override beside Energy. It converts values
  without changing the profile preference and saves in the existing kcal
  storage format; other screens continue using the profile's unit.
- Cycle averages keep interval/duration and any left-out count visible.
  Observation counts and explanations move into the existing Info dialog.

Validation: all 1,477 tests pass with Flutter 3.44.8 / Dart 3.12.2; analyzer,
format and diff checks pass. Coverage includes offline restart/barcode reuse,
hydration failure/profile switching, 14-day slot boundaries and imported-food
deduplication, both input energy units and per-serving conversion, and Cycle
presentation. Develop release APK rebuilt at
`build/app/outputs/flutter-apk/app-develop-release.apk`; packaged libraries
contain the new entry/offline code. No phone installation, iOS or remote CI run.

## October 7 checkpoint

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
  The October 8 Lifesum follow-up ignores household portion differences for
  gram-backed imports and compares all nutrients at six decimal places to
  remove conversion noise. Existing diary snapshots, IDs and totals remain
  untouched; serving-only imports keep distinct serving descriptions.
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


## Cycle design follow-up

- Track cycles moves into You > Display, directly below activity tracking.
  Visible wording uses "cycle" throughout settings, history and notifications.
- Cycle calendars match Diary's Monday-first week and current app locale.
  Past-cycle entry selects inclusive ranges while showing saved dates; single
  days, cross-month ranges and completing an ongoing cycle are supported.
- Starting estimates have a full-screen form with interval/duration explanations.
  Cancel, Save and Remove use consistent casing. Validation stays beside Save.
- Shared light sage rings surround Diary dates; forecast rings are paler.
  Nutrition dots, today/selection styling and the existing day actions remain.
- The overview, forms and settings use the existing card surfaces and theme.
  Tests cover ranges, overlap rejection, cancellation, setup validation and
  320px layouts through 2.0 text scaling in light and dark themes. Synthetic
  rendered previews were reviewed; the new design still needs phone acceptance.
- Stored history, backup schema and estimate calculations are unchanged.

The dashboard range-bar header now measures its text and compresses separator
spacing before wrapping burned energy. Font size and counter animation stay
unchanged. A Commissioner regression covers a single line at 250px content width
with four-digit burned energy; large accessibility text can still wrap.

Follow-up verification: all **1,449 tests pass**, analyzer clean, localization
generation succeeds and formatting reports 708 files with no changes. Reviewed
synthetic previews in both themes. The rebuilt develop release APK is
`build/app/outputs/flutter-apk/app-develop-release.apk` (88,983,729 bytes).
No phone installation or device acceptance was performed. Commits: `c56bb74a`
(opt-in placement), `6ff99239` (Cycle/calendar design), `9b858fa2` (header spacing).
