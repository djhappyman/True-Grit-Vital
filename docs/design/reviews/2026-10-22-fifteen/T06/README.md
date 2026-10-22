# T06: Export date shortcuts

Synthetic Flutter widget fixtures rendered with the real app fonts, a fixed
clock of 22 October 2026 12:00 UTC and the Europe/London display zone. The
fixture adult is "Alex"; no real records are used.

- `light-export.png` and `dark-export.png`: 390 px viewport, 30-day default
  selected.
- `light-export-full.png` and `dark-export-full.png`: the same selection with
  the full page height, including Format and Preview.
- `dark-export-narrow-double-text.png`: 320 px at 2x text, scrolled to the
  shortcuts. The three choices wrap onto two rows without overflow.

## Behaviour checked

- 30d and 90d include today; Year runs from 1 January through today. `Before`
  stays the exclusive next civil day, so the fields themselves state the range.
- Shortcuts update only the visible From and Before fields. They never
  generate, share or save; Preview and Save remain the existing reviewed
  artifact path.
- The values match `reportPeriodDates`, the Settings report shortcut, for
  ordinary days, leap day and both 2026 daylight-saving days. A range that
  cannot be represented is a typed failure instead of a clamped different day.
- An unavailable display zone or an unrepresentable device date leaves the
  fields unchanged and shows a recovery message.
- Changing the range after Change discards the earlier reviewed artifact and
  keeps the chosen format, content and private-note choice.
- Pending preparation replaces the selection, so shortcuts are unavailable
  until preparation ends or is cancelled.
- 320, 390 and 430 px at 2x text in both themes are exercised by
  `test/export_ui_test.dart`; these captures cover the 390 px and one 320 px
  visual state. Native device rendering is not measured here.

Lead review also waits for the observed device zone before defaulting dates,
preserves dates typed while that observation is pending, and rejects retained
shortcut callbacks during generation/review/handoff or after disposal.
