<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/icon/logo_stable_light.svg">
    <img alt="Stable" src="assets/icon/logo_stable_dark.svg" width="280" />
  </picture>
</p>

<p align="center">
  <a href="LICENSE" alt="License">
    <img src="https://img.shields.io/badge/license-GPLv3-blue" />
  </a>
  <img src="https://img.shields.io/badge/Flutter-3.41.7-02569B?logo=flutter&logoColor=white" alt="Flutter 3.41.7" />
  <img src="https://img.shields.io/badge/platforms-iOS%20%7C%20Android-lightgrey" alt="Platforms" />
  <img src="https://img.shields.io/badge/telemetry-none-brightgreen" alt="No telemetry" />
</p>

## What Stable is

Stable is a quiet nutrition tracker.

It logs food, activities, water and body measurements, shows you where the day landed, and sends no analytics or telemetry anywhere. No account, no crash reporting, no streaks nagging you back into the app.

Calories are shown as a **range**. Feedback stays neutral by design. Going over the range is just another kind of day, not a failure state.

Stable is built with Flutter for Android and iOS. It started as a fork of [OpenNutriTracker](https://github.com/simonoppowa/OpenNutriTracker), but has since been reworked into its own app.

> **Status:** Active development. Stable is not currently published to an app store, so expect rough edges if you build it from source.

## Privacy

Privacy is part of the design.

* **No telemetry.** No analytics, crash reporting, usage tracking or account system. Sentry and its related code have been removed entirely.
* **Barcode scanning stays on-device.** Stable uses [`flutter_zxing`](https://pub.dev/packages/flutter_zxing), backed by zxing-cpp. It does not depend on Google ML Kit or Play Services for scanning.
* **Local data is encrypted.** The Hive database uses AES encryption, with its key stored through `flutter_secure_storage`.
* **Network requests are deliberate.** Stable contacts food databases when you search for or scan a product that is not already cached locally.
* **Scanned products are cached.** Once a barcode is known locally, scanning it again does not require another lookup.
* **Exports are explicit.** Nothing leaves the app unless you ask it to. Body measurements are deliberately excluded from exports.
* **Delete means delete.** `Settings → Delete all my data` removes local ALL Stable data from the device.

## Features

### Track your day

* **Food diary** with Breakfast, Lunch, Dinner and Snack.
* Configurable meal splits, including Standard, OMAD, Five-small, Mediterranean, Two-meal and custom.
* Drag foods between meals and sort entries by time or macro contribution.
* **Quick add** for foods where you only need a name, calories and optional macros.
* **Custom foods, meals and recipes**, including barcode scanning inside the recipe builder.
* **Activities** from a categorised MET catalogue or custom calorie templates.
* **Water tracking** with exact volume adjustments.
* Optional **fasting timer**, with no streaks or targets.

### Scan food

Stable supports:

* EAN and UPC barcodes
* GS1 DataMatrix
* Manual barcode entry

If a barcode is unknown, you can either create a new food for it or connect it to an item you already have. The association is saved locally for next time.

### See what is happening

* **Today** view with calorie range, macros, water, fasting and meals.
* **Trends** for weight, measurements, water and intake.
* **Diary / Archive** for browsing previous days.
* **Micronutrients** for day and week views, with configurable goals and visibility.
* **Weight and body measurements** with optional target lines and calorie tapering.
* **Sources & References** for the calculations used by the app.

Tracked micronutrients currently include fibre, sodium, saturated fat, sugar, calcium, iron, potassium, vitamin D, vitamin B12 and magnesium.

### Make it yours

* Multiple local profiles with separate goals and history.
* Shared custom meal and recipe libraries between profiles.
* Light and dark themes.
* Material You on Android 12+.
* Sixteen accent presets plus custom hex colours.
* kcal or kJ.
* Metric or imperial units.
* Configurable start-of-day hour.
* Optional daily reminder.
* Biryani throughout, because obviously.

Stable currently supports nine languages:

English, German, Czech, Italian, Polish, Slovak, Turkish, Ukrainian and Chinese.

### Import and export

Stable can export tracked data as a zip containing:

* **JSON**, the canonical re-importable format
* **CSV**, for spreadsheets and other tools

See [`docs/export-format.md`](docs/export-format.md) for the format.

You can also:

* Import Stable exports again.
* Paste JSON for ad-hoc meal imports.
* Share individual meals and activities as QR codes.
* Import a Lifesum export archive.

The Lifesum importer shows a preview before writing anything, preserves days already tracked in Stable, and journals the import so it can be rolled back. Lifesum does not export actual water events, so estimated water data is clearly marked as estimated.

## Food data

| Source                                              | Notes                                                                                                                                                                        |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Open Food Facts](https://world.openfoodfacts.org/) | Text search and barcode lookup. Works without configuration.                                                                                                                 |
| Supabase reference backend                          | Multi-source backend for [USDA FoodData Central](https://fdc.nal.usda.gov/) and [Bundeslebensmittelschlüssel](https://www.blsdb.de) 4.0. Requires your own Supabase project. |
| USDA FoodData Central direct                        | Requires `FDC_API_KEY`. Not currently exposed in the UI.                                                                                                                     |

You can choose which sources Stable searches under **Settings → Food databases**.

No shared backend credentials are included in this repository. Open Food Facts and barcode scanning work out of the box. Supabase-backed sources remain disabled until you configure your own project.

The reference backend is based on [OpenNutriTracker-Backend](https://github.com/simonoppowa/OpenNutriTracker-Backend). Setup instructions are in [`docs/supabase-self-hosting.md`](docs/supabase-self-hosting.md).

## Building from source

Stable currently targets **Flutter 3.41.7**, pinned in `.fvmrc`.

Using another Flutter version may resolve different package versions, so using the pinned SDK is recommended.

> The current Stable work lives on the `feature/lifesum-import` branch. `main` still tracks upstream OpenNutriTracker.

```sh
git clone https://github.com/vurglepuddle/StableNutri.git
cd StableNutri

cp .env.example .env
just install
just build

flutter run
```

`.env.example` contains placeholders for code generation. Fill in only the services you want to use:

```text
FDC_API_KEY
SUPABASE_PROJECT_URL
SUPABASE_PROJECT_ANON_KEY
```

After changing `.env`, run:

```sh
just build
```

The generated `env.g.dart` is intentionally gitignored.

Common development commands:

```sh
just format   # dart format
just test     # full test suite
just ci       # install, format check, intl check, build, analyze and test
```

Environment setup for Android, emulators and IDEs is covered in [GettingStarted.md](GettingStarted.md).

Architecture and development notes live in [CLAUDE.md](CLAUDE.md).

## Contributing

Issues and pull requests are welcome.

See [CONTRIBUTING.md](CONTRIBUTING.md) before changing localisation files. The generated localisation files under `lib/generated/` are maintained manually, so do not run the intl generator over them.

Code uses Dart's default **80-column** formatting.

Before submitting changes:

```sh
just ci
```

## Disclaimer

Stable is not a medical application. The data it provides is not medically validated and should be used with caution.

Maintain a healthy lifestyle and consult a qualified professional if you have health concerns. Use during illness, pregnancy or lactation is not recommended.

Stable is still in active development. Bugs, errors and crashes may occur.

## Acknowledgments

Stable began as a fork of [OpenNutriTracker](https://github.com/simonoppowa/OpenNutriTracker) by Simon Oppowa. Great foundation, and a lot of Stable still owes its existence to that work.

Food data is provided by or derived from:

* [Open Food Facts](https://world.openfoodfacts.org/)
* [USDA FoodData Central](https://fdc.nal.usda.gov/) (CC0)
* [Bundeslebensmittelschlüssel](https://www.blsdb.de) 4.0 (CC BY 4.0, © Max Rubner-Institut)

[Anuvaad INDB](https://anuvaad.org.in) (CC BY 4.0) and [TBCA Brazil](https://www.tbca.net.br) (USP/FoRC) are prepared as future sources.

Dietary Reference Intake values come from the U.S. National Academies' Institute of Medicine tables.

Barcode decoding uses [zxing-cpp](https://github.com/zxing-cpp/zxing-cpp) through [`flutter_zxing`](https://pub.dev/packages/flutter_zxing).

## License

Stable is licensed under the GNU General Public License v3.0, inherited from OpenNutriTracker.

See [LICENSE](LICENSE).
