# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Stable** is a Flutter mobile app (iOS/Android) for nutritional tracking, forked from
[OpenNutriTracker](https://github.com/simonoppowa/OpenNutriTracker) and being reworked into its own product. Food data
comes from Open Food Facts and a multi-source Supabase backend (USDA FoodData Central, German BLS, and more — see the
[OpenNutriTracker-Backend](https://github.com/simonoppowa/OpenNutriTracker-Backend) repo). All user data is stored
locally in an AES-encrypted Hive database.

The rebrand is **partial and deliberate**, so expect both names in the tree:

- The Dart package is still `opennutritracker` — every import is `package:opennutritracker/...`. Do not rename it.
- `upstream` remotes, the README, the launcher icons and the `appTitle` l10n string still say OpenNutriTracker.
- Code comments, the design docs and the user-facing copy increasingly say Stable. New work should say Stable.

Flutter version: **3.41.7** (pinned in `.fvmrc`). The unqualified `flutter` on the maintainer's PATH is a *different*,
newer SDK — always invoke the pinned one explicitly, and pass `--no-pub` to analyze/test so a stray resolve doesn't
rewrite `pubspec.lock`. See `Design/session-handoff-2026-08-03.md` for the exact local path.

The durable working notes for this project live in `../Design/session-handoff-2026-08-03.md` (newest section first).
Read it before starting; append to the top when finishing.

## Commands

Common tasks live in the `justfile`:

```sh
just install       # flutter pub get
just build         # dart run build_runner build
just format        # dart format ./lib/core ./lib/features ./lib/l10n ./test
just test          # flutter test
just check_intl    # verify generated intl files are unchanged (used in CI)
just ci            # install, format check, intl check, build, analyze, test
```

Run a single test file, or analyze:

```sh
flutter test test/unit_test/tdee_calc_test.dart
flutter analyze
```

## Code Style

**80 columns** — `dart format`'s default. `analysis_options.yaml` deliberately carries no `formatter: page_width` key,
so the default applies and no configuration can drift out of sync with it.

Earlier docs claimed 120, and a large minority of files had been checked in that way; the tree was normalised to 80 in
one standalone commit on 2026-09-05, so `just format --set-exit-if-changed` (and therefore `just ci`) now passes on a
clean tree. If you ever see `just format` rewriting files you did not touch, something has regressed — say so rather
than committing the churn alongside your change.

`just format` deliberately targets only `./lib/core ./lib/features ./lib/l10n ./test`. **Never run `dart format` on
`lib/generated/`** — those files are hand-maintained against a different style (see Localization).

## Environment Setup

Copy `.env.example` to `.env` and fill in real values before running:

```sh
cp .env.example .env
```

The template carries placeholders that have no real-world effect — they exist so `envied`'s codegen finds every key on a
fresh clone. Replace them:

```
FDC_API_KEY="YOUR_KEY"        # USDA Food Data Central API key (direct FDC source, not actively used in UI)
SENTRY_DNS="DNS_URL"
SUPABASE_PROJECT_URL="PROJECT_URL"
SUPABASE_PROJECT_ANON_KEY="ANON_KEY"
```

`.env` is gitignored (`.gitignore` matches `*.env`), so real secrets won't be committed accidentally. After editing it,
run `just build` to regenerate `lib/core/utils/env.g.dart` (also gitignored). The `envied` package obfuscates all secret
values at compile time. **Never read, stage or commit `.env`.**

## Code Generation

Run `just build` (`dart run build_runner build`) whenever you add or modify any of the source files listed below. Every
generated file starts with `// GENERATED CODE - DO NOT MODIFY BY HAND` or an equivalent header — never edit them
directly. The one exception is the intl output, which is maintained by hand (see Localization).

If `build_runner` fails with `PackageNotFoundException: hive` after pulling from an older checkout, the build cache is
stale from the pre-`hive_ce` days:

```sh
rm -rf .dart_tool/build
dart run build_runner build
```

### What gets generated and when

| Trigger                            | Generated file(s)                                                                                         | Tool                |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------- | ------------------- |
| Any `@HiveType` / `@HiveField` DBO | `<dbo_file>.g.dart` alongside the source                                                                  | `hive_ce_generator` |
| Any new DBO added anywhere         | `lib/hive_registrar.g.dart` — the `HiveRegistrar` extension that calls `registerAdapter()` for every type | `hive_ce_generator` |
| Any `@JsonSerializable` DTO        | `<dto_file>.g.dart` alongside the source                                                                  | `json_serializable` |
| `.env` file edited                 | `lib/core/utils/env.g.dart` (**gitignored** — must regenerate after every clone)                          | `envied_generator`  |

**DBO files** live in `lib/core/data/dbo/` and `lib/core/data/data_source/` (one `.g.dart` per file). Whenever you add a
`@HiveField` or change a field's type, regenerate — otherwise the binary reader/writer will be out of sync.

**`lib/hive_registrar.g.dart`** is checked in (no machine-specific content). Regenerate it any time you add or remove a
DBO type.

**DTO files** live under `lib/features/add_meal/data/dto/` (`off`, `fdc`, and Supabase `sp` subfolders). Regenerate when
you add or change API response fields.

## Localization

Source strings live in `lib/l10n/intl_en.arb` (plus locale ARBs for `de`, `cs`, `it`, `pl`, `sk`, `tr`, `uk`, `zh`).
Generated Dart lives in `lib/generated/intl/` and `lib/generated/l10n.dart`.

The files in `lib/generated/` are **maintained by hand** — do not regenerate them with
`intl_translation:generate_from_arb`, as the generator's output conflicts with the checked-in formatting. `just run_intl`
is deliberately a no-op alias for `just format`.

**To add a string**, edit three files by hand:

1. `lib/l10n/intl_en.arb` — the key, plus an `@key` block with `placeholders` if it takes arguments.
2. `lib/generated/l10n.dart` — a getter (no args) or method (with args) wrapping `Intl.message`.
3. `lib/generated/intl/messages_en.dart` — a `MessageLookupByLibrary.simpleMessage(...)` entry, or a new `mNN` function
   for parameterised strings, plus the map entry.

English-only additions are the established pattern; the other locales fall back to English at runtime for keys they
don't carry. Then run `just check_intl` (which is just `git diff --exit-code` over those paths) before committing.

Note: the `SupportedLanguage` enum maps device locales to `food_translation` locales via `SPConst.translationLocaleOf`
(`en` reads `food_summary.name` directly; the rest query translations, falling back to English).

## Accessibility identifiers for interactive widgets

Every new interactive widget gets a `Semantics(identifier: 'kebab-case-id')` wrapper so automated UI drivers (ADB
uiautomator on Android, Appium / XCUITest on iOS) can find it by a stable handle and tap by coordinate. The `identifier`
is never spoken by TalkBack or VoiceOver — it carries no user-facing label, only a test handle — and on iOS it maps to
`accessibilityIdentifier`, so this works cross-platform.

The minimal pattern:

```dart
Semantics(
  identifier: 'feature-action',
  child: <interactive widget>,
)
```

### What's in scope

| In scope (must label) | Out of scope (don't bother) |
|---|---|
| `ListTile` / `InkWell` / `GestureDetector` with an `onTap` | Pure display — `Text`, `Icon`, `Image`, `Divider`, charts |
| Buttons — `ElevatedButton`, `TextButton`, `IconButton`, `FloatingActionButton`, `FilledButton` (when they have `onPressed`) | Layout — `Container` without `onTap`, `Padding`, `SizedBox`, `Row`, `Column` |
| Input — `TextField`, `TextFormField`, `Slider`, `Switch`, `SwitchListTile`, `Checkbox` (the actual checkbox, not its label) | Generated code (`*.g.dart`, `messages_*.dart`, `l10n.dart`) |
| Selection — `ChoiceChip`, `FilterChip`, `RadioListTile`, `SegmentedButton`, `DropdownButton` | Theming, transitions, decorative wrappers |
| Bottom sheets, dialog action buttons (Save/Cancel/OK) | Items inside `ListView.builder` / `GridView.builder` (see below) |

### Naming convention

- `<surface>-<element>` for static screen widgets — `profile-weight`, `nav-home`, `settings-units`, `onboarding-button`.
- `<feature>-<action>` for feature-specific actions — `weight-history-add`, `paste-json-submit`, `recipe-builder-save`.
- `<surface>-<element>-<variant>` for variants — `onboarding-gender-female`, `onboarding-activity-active`.

Keep the identifier locale-independent — never include translatable strings in the id. Note that the bottom-nav ids
still read `nav-home` even though the destination is now labelled **Today**; the id is an automation handle and was kept
stable through the rename.

### Dynamic lists

For widgets built inside a `ListView.builder` / `GridView.builder` (intake cards, meal results, water cups, weight log
entries), label the **parent surface** (e.g. `home-meals-breakfast-list`, `home-water-cups`) — not every child.
Verifiers scope into the list via the parent identifier, then find the specific item by visible text or `content-desc`
via the `_tap_text` helper. This avoids identifier churn when item counts change.

### Dialog action buttons inside system dialogs

Material's `DatePicker`, `AlertDialog`, etc. expose their OK / Cancel buttons via the platform's own accessibility tree
— those don't need `Semantics(identifier:)` wrappers. Find them with `_tap_text`, which checks both `text` and
`content-desc`.

### Don't double-up roles

Skip `button: true`, `textField: true`, etc. when the child widget already publishes that role. `ChoiceChip`,
`FloatingActionButton`, `TextFormField`, `ElevatedButton` and `SegmentedButton` all provide their own role semantics —
stacking the flag risks TalkBack announcing it twice ("button, button"). The rule is
`Semantics(identifier: '...', child: widget)` and nothing else, unless a gotcha below applies.

### The `container: true` gotcha

When the immediate parent of `Semantics(identifier:)` is `Expanded`, a flexible `Container` filling its parent, or any
other layout-greedy widget, the Semantics node inherits the parent's bounds rather than the child's render box.
`adb shell uiautomator dump` will then report the widget at the entire parent area, and coordinate taps land mid-screen.

Symptom: a button clearly at the bottom of the screen reports `bounds=[0,145][1440,3036]` (full screen).

Fix:

```dart
Semantics(
  identifier: 'foo',
  container: true,  // <- creates a separate semantic node with tight bounds
  child: widget,
),
```

Or restructure so the Semantics descendant has tight constraints (e.g. wrap in `Align`).

Always verify with `adb shell uiautomator dump /sdcard/d.xml && adb pull /sdcard/d.xml /tmp/d.xml && grep your-id
/tmp/d.xml` after adding a label inside a flex container. Reasonable bounds are tens to a few hundred pixels a side, not
screen-sized.

### Flutter widgets on Android use `content-desc`, not `text`

In the uiautomator dump, the visible text of Flutter widgets is reported under `content-desc`. System dialogs
(DatePicker, AlertDialog) use `text`. Test drivers that find widgets by label must check both.

### Form fields drift between taps

Flutter `TextField` / `TextFormField` widgets all report screen-wide `bounds` (the `container: true` gotcha applied to
every input). Tapping a field by hard-coded coordinates from an earlier dump only works once — the moment the keyboard
appears, every layout shifts and the next tap lands on the wrong row.

The `adb-driver.sh` helpers `tap_field_by_hint`, `enter_text_in_field` and `fill_fields_by_hint` re-dump the UI before
every tap and locate the field by its placeholder `hint` attribute. They also hide the keyboard between fields so the
next hit target is calculated against the post-IME layout.

```bash
source tools/adb/adb-driver.sh
fill_fields_by_hint \
  'Meal name'     'Greek%syoghurt' \
  'Energy (kcal)' '100' \
  'Carbohydrates' '4' \
  'Fat'           '5' \
  'Protein'       '10'
```

Pass `clear` as a third argument to `enter_text_in_field` when overwriting an existing value.

### ADB test tooling

Reusable ADB scripts live in `tools/adb/`:

| Script | Purpose |
|--------|---------|
| `adb-driver.sh` | Core driver library: `tap_id`, `wait_for_id`, `enter_text_at`, `_tap_text`, `screenshot`, `list_ids`, plus the form-field helpers above. Source from any test script. |
| `walk-onboarding.sh` | Walks the onboarding flow and lands the app on the main screen. Exports `walk_onboarding()`. |
| `run-branch-tests.sh` | Sequential smoke-test runner: builds a debug APK, installs it, walks onboarding, runs a branch-specific probe. |
| `quiet-logs.sh` | Silences third-party log tags (CameraX presence, Firebase transport) that flood `flutter run`. `--restore` undoes it. Device-side and reset by a reboot. |

`DEVICE` defaults to the first device from `adb devices` when not set.

Note that `flutter run` prints every logcat line from the app's *process*, which includes Google Play Services
libraries linked into the app — those tags are not Stable's code. If the output is drowning in them, run
`quiet-logs.sh` rather than assuming the app is misbehaving.

### Enforcement

Convention, not lint. New widgets without identifiers aren't a merge blocker, but the per-branch feature verifier won't
be able to drive them.

## Architecture

Clean Architecture with a feature-based module structure.

### App startup sequence

`main()` → `initLocator()` → Hive init (AES key from `flutter_secure_storage`) → open the **global** boxes →
`bootstrapActiveProfile()` resolves the active profile and opens its **per-profile** box-set → Supabase init → prune the
stale remote-search cache → restore scheduled notifications → check `UserDataSource.hasUserData()` → route to
`onboarding` (first run) or `main` (returning user).

Sentry is enabled only in **release mode**, and only if the user consented to anonymous data collection during
onboarding.

### Navigation shell

`MainScreen` hosts an `IndexedStack` behind a custom `BottomAppBar` with a notch for the centre **Add** FAB. There are
**four** persistent destinations, defined by `MainDestination` in `lib/core/presentation/main_navigation.dart`:

| Destination | Widget | Feature folder |
|---|---|---|
| **Today** (`nav-home`) | `HomePage` | `features/home` |
| **Trends** (`nav-trends`) | `TrendsPage` | `features/trends` |
| **Library** (`nav-library`) | `RecipesPage` | `features/recipes` |
| **You** (`nav-you`) | `ProfilePage` | `features/profile` |

**Diary / Archive is not a tab** — it is a full screen pushed from Today (the calendar action in the app bar).
`MainNavigationScope` is an `InheritedWidget` that lets descendants (e.g. the You page) switch an existing shell tab
instead of pushing a duplicate copy of that destination.

All other screens are named routes in `NavigationOptions`, registered in `main.dart`.

### Directory structure

```
lib/
  core/           # Shared across all features
    data/
      data_source/  # Hive box wrappers (local DB access)
      dbo/          # Hive-annotated database objects (suffixed DBO)
      repository/   # Core repositories (user, intake, config, profile, water, ...)
    domain/
      entity/       # Plain domain models (suffixed Entity)
      usecase/      # Business logic operations
    presentation/
      main_screen.dart      # Bottom-nav shell (Today / Trends / Library / You)
      main_navigation.dart  # MainDestination enum + MainNavigationScope
      widgets/              # Shared UI components (AppCard, charts, dialogs, ...)
    styles/       # app_palette.dart, app_theme.dart, dimens.dart
    utils/        # locator.dart (DI), hive_db_provider.dart, profile_bootstrap.dart,
                  # env.dart, calc/, bounds/, ...
  features/       # One folder per screen/flow
    home/         # "Today": calorie-range ring, macros, water card, fasting chip, meal sections
    diary/        # Calendar-based archive, per-day nutrients, read-only water
    trends/       # Weight, measurement, water and intake charts over a range
    profile/      # "You": stats, BMI, goals, weight history, profile management
    measurements/ # Body-measurement log + trend chart
    recipes/      # "Library": saved recipes and custom meals
    add_meal/     # Food search (text + barcode) and meal logging
    meal_detail/  # Nutritional detail for a food item
    edit_meal/    # Edit a logged intake, custom meal create / template
    scanner/      # Barcode camera scanner (with manual entry fallback)
    add_activity/ # Log physical activity, including custom kcal templates
    activity_detail/
    fasting/      # Intermittent-fasting timer with a content-warning gate
    settings/     # Settings, export/import, Lifesum import, day-start, theme
    onboarding/   # First-run setup
  generated/      # Intl files — maintained by hand (see Localization)
  l10n/           # Source ARB translation files
```

Each feature follows the same three layers: `data/` (DTOs, data sources), `domain/` (entities, use cases),
`presentation/` (BLoC + widgets). Smaller features skip the layers they don't need.

### State management

**flutter_bloc** throughout. Screens have a `*Bloc` with `*Event` / `*State` files. A few small surfaces
(`WaterCard`, dialogs) are plain `StatefulWidget`s that call bloc methods directly.

### Dependency injection

**GetIt**, all registered in `lib/core/utils/locator.dart` (`initLocator()`), called once at startup. Registration order
matters — data sources, then repositories, then use cases, then BLoCs.

- **`registerLazySingleton`** — screen-persistent BLoCs (Home, Profile, Recipes, Trends, CustomMeals, Onboarding,
  Settings, Diary, CalendarDay) plus every repository and use case. `HomeBloc` and `DiaryBloc` cross-reference each
  other via the locator at runtime.
- **`registerFactory`** — per-navigation BLoCs (MealDetail, Scanner, EditMeal, AddMeal, Products, Food, Activities,
  ActivityDetail, RecipeBuilder, RecipeDetail, LifesumImport, ExportImport, Fasting). A fresh instance per navigation.

### Profiles and the two-tier local database

**hive_ce** (the maintained community fork of Hive), AES-256 encrypted. `HiveDBProvider` splits boxes into two tiers.

**Global boxes** — one set, shared by every profile:

| Box | Payload | Purpose |
|---|---|---|
| `ProfileBox` | `ProfileDBO` | Registry of profiles (id, name, image, `boxSuffix`) |
| `AppConfigBox` | `ConfigDBO` | Device-wide preferences: theme, accent, language, units, energy unit, notifications, consent, legal acceptances, view toggles |
| `CustomMealBox` | `MealDBO` | Shared library of user-saved custom meals |
| `RecipeBox` | `RecipeDBO` | Shared library of user recipes |
| `CustomActivityTemplateBox` | `CustomActivityTemplateDBO` | Shared reusable custom-kcal activity templates |
| `CachedOffMealBox` | `MealDBO` | Open Food Facts response cache |
| `CachedOffMealTimestampsBox` | `int` | Cache "last touched" timestamps; drives the 90-day TTL sweep |

**Per-profile boxes** — one set per profile, listed in `HiveDBProvider.perProfileBoxNames`:

| Box | Payload | Purpose |
|---|---|---|
| `ConfigBox` | `ConfigDBO` | *Personal* nutrition goals only: kcal adjustment, macro split, per-meal kcal shares, water goal, intake range, weight corridor |
| `IntakeBox` | `IntakeDBO` | Meal log entries (link to `MealDBO`, typed by `IntakeTypeDBO`) |
| `UserActivityBox` | `UserActivityDBO` | Logged physical activities |
| `UserBox` | `UserDBO` | Body stats: height, weight, birthday, gender, PAL, goal |
| `TrackedDayBox` | `TrackedDayDBO` | Per-day calorie/macro running totals for the diary calendar |
| `WeightLogBox` | `WeightLogDBO` | Weight history points |
| `BodyMeasurementLogBox` | `BodyMeasurementLogDBO` | Waist, hips, chest, etc. |
| `WaterIntakeBox` | `WaterIntakeDBO` | One row per drink, powering the Today water card |
| `FastingBox` | `FastingSessionDBO` | Fasting sessions, current and historical |
| `LifesumImportJournalBox` | `String` | Journal of what a Lifesum import wrote, so it can be rolled back |

**How the split works.** Per-profile boxes are named by appending the active profile's `boxSuffix`. The **first profile
carries an empty suffix**, so its boxes resolve to the original unsuffixed names already on disk — that is what lets an
existing single-user install upgrade into a multi-profile build with nothing copied or migrated. Switching profiles
closes the current per-profile set and opens the target's, so the getters always hand back the active profile's boxes.
Reads during that window throw a descriptive error via `_requireBox` rather than Hive's opaque closed-box error.

`ConfigDataSource` merges the two config boxes on read (shared fields from `AppConfigBox`, personal fields from the
profile's `ConfigBox`) and writes the merged copy to both; because reads always source each field from its authoritative
box, the redundant copy is ignored and the two can't disagree on anything that matters.

When adding a new `@HiveType`, assign an unused `typeId` — **0–23 are taken**. Decide deliberately whether the box is
global or per-profile, and add it to `perProfileBoxNames` if it's the latter.

### Food data sources

`ProductsRepository` aggregates three sources via `SearchProductsUseCase`:

| Source           | Class              | Notes                                                                               |
| ---------------- | ------------------ | ----------------------------------------------------------------------------------- |
| Open Food Facts  | `OFFDataSource`    | REST API — text search + barcode lookup                                             |
| Supabase backend | `SpFoodDataSource` | Full-text search on `food_summary` + `food_translation` (multi-source: FDC, BLS, …) |
| USDA FDC direct  | `FDCDataSource`    | Requires `FDC_API_KEY`; not actively surfaced in the UI                             |

`SearchProductsUseCase.searchFDCFoodByString` uses the **Supabase** source, not the direct FDC API. Users choose which
backend sources to search in Settings → Food databases (`SPConst.settingsSelectableFoodSources`).

### Calories: a range, not a point

Today's gauge shows an **intake range** (e.g. "Range 1350–1600 kcal"), not a single target. Calculation utilities live
in `lib/core/utils/calc/`:

- **TDEE** — `TDEECalc.getTDEEKcalIOM2005()` (IOM 2005, gender-specific; `caloriesProfile` covers non-binary users). A
  WHO 2001 formula exists but is unused.
- **Calorie goal** — `CalorieGoalCalc`: TDEE + weight-goal adjustment (±500 kcal, or derived from
  `weeklyWeightGoalKg` at ~1100 kcal/day per kg/week) + optional user offset + today's burned activity kcal. When
  calorie taper is enabled, the adjustment eases to zero between 5 kg and 1 kg from the target weight.
- **Range semantics** — `StableRangeCalc.classify()` returns below / within / above plus the distance to the range;
  `progressTowardUpper()` drives the ring. Bounds are inclusive, and `lower == upper` is valid so an upgraded profile
  keeps its legacy point target until the user picks a real range.
- **Floor warning** — `CalorieGoalCalc.isBelowRecommendedDailyKcalFloor()` backs the low-kcal warning card.
- **Macro defaults** — 60% carbs / 25% fat / 15% protein of total kcal. Per-macro overrides in `ConfigEntity`.
- **MET** — `MetCalc` converts MET × weight × hours to burned kcal.
- **Day boundary** — `DayBoundaryCalc` maps a timestamp to its *logical* day for users on a non-midnight boundary
  (Settings → Calculations). Anything that aggregates "today" must go through it, using the total-minutes variant so a
  04:30 setting is honoured exactly.

### Design system

`lib/core/styles/` carries the "friendly-flat" look:

- **`app_palette.dart`** — `AppPalette` for light and dark: a warm-neutral canvas, a surface ladder, hairline borders,
  one soft shadow. A single vivid `accent` is user-overridable (accent picker / Material You) via `withAccent()`.
  Semantic colours — the macro trio (carbs amber, fat coral, protein teal) and `waterColor` — are **fixed** so the
  dashboard reads the same whatever accent is chosen. `colorScheme` maps the palette onto Material 3.
- **`app_theme.dart`** — `appTextTheme(AppPalette)` and `buildAppTheme(AppPalette)`. Type is **Nunito** throughout.
- **`dimens.dart`** — spacing, radii, `minTouchTarget`, and `AppMotion` (durations + emphasized curves). Use these
  tokens rather than raw numbers.
- **`AppCard`** (`core/presentation/widgets/app_card.dart`) is the one card surface. Dashboard items are `AppCard`s
  with 16 px page margins.

`lib/core/styles/fonts.dart` (a Poppins `TextTheme`) is **dead** — nothing imports it, and `fonts/` still ships the full
Poppins family plus Fredoka for the same reason. Don't add new references to it.

Animations should be **finite**. Looping or idle animations make `pumpAndSettle` hang and drain battery; the water card
deliberately uses one-shot, self-damping motion instead.

### SVG assets must be flattened

`flutter_svg` does **not** implement CSS. Illustrator and Figma export `class="cls-1"` plus a `<style>` block by
default, and such a file renders as **nothing at all** — silently, with only an `unhandled element <style/>` line in the
log. Before checking any SVG into `assets/`, inline the class rules as presentation attributes (`fill="#173525"`) and
delete the `<style>` block. `flutter_svg` also has no reliable `<text>` support, so outline all type.

Because a whole picture is the smallest thing `flutter_svg` can tint, artwork that must change with the theme ships as
**two authored variants** rather than one recoloured file — see `StableWordmark`, whose asset names describe the canvas
they sit on, not the ink they carry.

### Data export / import

Settings exports a `.zip` bundling intakes, activities, tracked days and recipes as both JSON (canonical,
re-importable) and CSV (flat, for spreadsheets) — see [`docs/export-format.md`](docs/export-format.md). Import accepts
the same zip and merges into the existing boxes. Profile body stats (height, weight, birthday, PAL, goal) are
intentionally **not** exported. Settings → Import also accepts a pasted JSON blob for ad-hoc meal imports.

**Lifesum import** (`lib/features/settings/domain/lifesum_import/`) reads a Lifesum export archive and stages a
reviewable preview before writing: parsers per record type (food, activity, recipe, measurement), a manifest, a
coordinator, an executor, and a **journal** persisted to `LifesumImportJournalBox` so a partial import can be rolled
back. Days already tracked in Stable are kept. Water is not in the export, so it is *estimated* and its entries are
tagged with a `lifesum-estimated-water-` id prefix; the UI labels them as estimates and never presents their synthetic
timestamps as real drink times.

### ID prefixes worth knowing

Several features encode provenance in the entity id rather than a schema column. Check these before changing id
generation:

- `lifesum-estimated-water-…` — an estimated water entry from a Lifesum import, not a real logged drink.
- `water-trimmed-…` — the leftover of a drink partly removed by tapping a full cup on the water card.

Both are skipped by `GetWaterIntakeUsecase.getQuickAddAmountMl()`, which infers the cup size from the last drink the
user actually chose.

## Naming Conventions

| Suffix                     | Meaning                                                       |
| -------------------------- | ------------------------------------------------------------- |
| `DBO`                      | Database Object — Hive-annotated local storage model          |
| `DTO`                      | Data Transfer Object — JSON-deserialized API response model   |
| `Entity`                   | Domain model — plain Dart class used in business logic and UI |
| `Bloc` / `Event` / `State` | BLoC pattern state management files                           |
| `Usecase`                  | Single-responsibility business logic class                    |
| `Repository`               | Mediates between data sources and use cases                   |
| `DataSource`               | Direct access to one data store (Hive box or HTTP API)        |
| `Calc`                     | Pure, static calculation helper in `core/utils/calc/`         |

## Testing

`flutter test` runs ~950 tests. They live in three places, by history rather than by rule: `test/unit_test/`,
`test/widget_test/`, and a mirrored `test/features/...` / `test/core/...` tree. Put new tests wherever the code they
cover already has neighbours.

Useful conventions in this suite:

- Fakes are hand-written `implements` classes with `noSuchMethod`, not mock-library generated. A fake that must never be
  written to throws from `noSuchMethod` — that turns an unexpected write into a test failure.
- Layout regressions are caught by pumping at a 320 px viewport with `TextScaler.linear(1.6)` and asserting
  `tester.takeException()` is null. Do this for any new card or row.
- To check something drawn by a `CustomPainter`, read the painter off the `CustomPaint` widget and assert on its fields
  (via `dynamic` when the painter class is private) rather than golden-matching.
- For a one-off visual check, render the widget to a golden PNG with `--update-goldens`, look at it, then delete the
  scaffolding. Goldens are not checked in.
- `integration_test/app_boot_test.dart` is the only integration test.
