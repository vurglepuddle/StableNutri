# Android quick add

Open Stable once after installing, then long-press the Android home screen,
choose **Widgets → Stable quick add**, and place the widget. It defaults to
4 × 1 and resizes up to 5 × 2. Three joined tiles show water, food and exercise
at every size: a label, today's value and a plus. From about two rows the
number and unit stack in larger type. The whole tile is the tap target.

- **Water +** saves one cup without opening the app. The cup repeats the latest
  manually logged drink size, using the existing 250 ml default.
- **Food +** opens Add Food directly. Local time selects breakfast (05:00–10:59),
  lunch (11:00–15:59), dinner (16:00–21:59), or snack otherwise. Disabled meal
  slots are skipped. The diary's configured day boundary still determines the
  logged day.
- **Exercise +** opens Add Activity directly.

The widget follows the active profile, energy units, locale and accent. Tiles
use the palette's deep water blue, the accent (or Material You accent) for food,
and coral for exercise, in both themes; a light custom accent gets dark text.
Text follows the system font scale up to 1.2× in one row and 1.5× in two.
Each tile's description names the action and includes its value. Water spells
its unit out ("1 litre", "1.2 litres"): Stable sends every plural form of the
translated unit, and the widget picks the one for its own total with Android's
plural rules, because cups tapped while Stable is closed change that total.

Settings → Display → Show Water Tracking and Show Activity Tracking also hide
the water and exercise tiles. The remaining tiles widen and keep the widget's
rounded outer corners; food always shows, so the widget is never empty.

The resize limit is the launcher grid, not a dp width: launchers take the
smallest span across portrait and landscape, and landscape cells are wide
enough that a dp limit meant for five phone columns rounds down to four.

Water taps are durably stored in an Android outbox, with the original timestamp,
profile and unique ID. The widget updates immediately. Stable imports these
entries through `AddWaterIntakeUsecase` on resume/load, then acknowledges the IDs
together with refreshed totals. Replaying an interrupted import overwrites the
same Hive entry instead of adding a second cup. There is no second Flutter
isolate concurrently opening the encrypted database.

Food and exercise totals refresh from HomeBloc. Android also refreshes the
cached view periodically and on date/time changes. After a logical day changes,
unrefreshed values say “Open Stable” instead of showing yesterday's totals.
Profile switches clear the displayed snapshot; deleting a profile also removes
its pending widget entries.

Checked on the user's phone: the tile design, all three tiles, and water taps
with Stable closed. Still to check: 5 × 1 and 5 × 2, the large-font setting, a
custom accent, profile switching, and hiding water and exercise in Settings.
