# Android quick add

Open Stable once after installing, then long-press the Android home screen,
choose **Widgets → Stable quick add**, and place the widget. It can be resized;
a tall, narrow size uses three rows instead of three columns.

- **Water +** saves one cup without opening the app. The cup repeats the latest
  manually logged drink size, using the existing 250 ml default.
- **Food +** opens Add Food directly. Local time selects breakfast (05:00–10:59),
  lunch (11:00–15:59), dinner (16:00–21:59), or snack otherwise. Disabled meal
  slots are skipped. The diary's configured day boundary still determines the
  logged day.
- **Exercise +** opens Add Activity directly.

The widget follows the active profile, energy units, locale, theme and accent.
Its default surfaces, spacing and Commissioner font match Stable. Plus buttons
have 52 dp touch targets and descriptions that include the section's value.

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

Phone checks: add/resize the widget in the launcher; tap water with Stable
closed, then reopen and verify one timestamped entry per tap; launch food and
exercise from both cold and warm starts; check the device's large-font setting,
dark mode, and profile switching. No Android device was connected during the
implementation session.
