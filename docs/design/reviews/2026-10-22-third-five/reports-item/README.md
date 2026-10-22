# Substance report entry

22 October 2026, D20b. Based on `55f84cf` plus the assignment commit. No
dependency, schema, event-detail or lab change. The canonical Reports page and
report controller remain the only report selection and generation path.

## Behaviour

- The substance overview overflow now has a one-word `Report` command beside
  the existing Combine and Stock commands.
- It opens the existing Reports editor with template R01, exactly one item ID,
  the current display zone and the editor's default range: 1 January in the
  display year through the current display day. The range is visible and
  editable before Preview. Nothing is generated automatically.
- The selected full name is shown above the editor content with `Only this item
  is included.` Long names wrap at narrow widths and 2x text.
- Private notes, files, supporting records and stock details remain off; they
  are the existing explicit toggles.
- The URL seed uses `item`, `template`, `from`, `before` and `return` query
  parameters. `item` is accepted only as one identifier matching the existing
  `ReportSelection` identifier rule. A malformed, missing, deleted or foreign
  item shows a recovery page and never falls back to all items.
- A different active selection shows `Replace report?` and keeps the existing
  selection until Replace. A busy report is identified without replacement.
  Lock prevents replacement or navigation. The whole-item guard mirrors the
  existing event shortcut; `event_pages.dart` is unchanged.
- Opening the same selection again needs no replacement question. A generated
  artifact for the same selection is not cleared by re-entering the editor.
- Back pops the pushed report so the overview section that opened it remains
  selected. A direct link with no stacked overview goes to the explicit return
  location.
- A date range that cannot be represented shows the item date recovery instead
  of throwing. No first-dose date is assumed or used to narrow the range.

## Verification

- `./tool/flutterw test --no-pub test/report_item_entry_test.dart`
  passed 18 checks: exact single-item selection and defaults, display-zone
  midnight and range edge, URI round-trip and invalid IDs, missing/foreign item
  recovery, direct URL replacement, impossible range, busy report, lock during
  confirmation, same-selection return, Back section retention, 320/390/430 at
  2x text in both themes, and capture isolation.
- `./tool/flutterw test --no-pub test/design_substance_overview_test.dart`
  passed 18 checks.
- `./tool/flutterw test --no-pub test/report_item_entry_test.dart
  test/reports/reports_page_test.dart
  test/reports/report_event_selection_test.dart
  test/event_report_entry_test.dart test/design_substance_overview_test.dart`
  passed 66 checks in the final batch.
- `./tool/flutterw test --no-pub test/reports/report_controller_test.dart
  test/report_stock_capture_test.dart test/single_user_ui_test.dart`
  passed 14 checks.
- `./tool/flutterw analyze` reported no issues.

## Captures

Synthetic records only, captured with:

```
./tool/flutterw test --no-pub test/report_item_entry_test.dart \
  --plain-name "item report captures use synthetic records" \
  --dart-define=VITAL_REPORT_ITEM_CAPTURE=/tmp/opencode/report-item-capture
```

- [Light overview action](light-item-report-action.png)
- [Dark overview action](dark-item-report-action.png)
- [Light report selection](light-item-report.png)
- [Dark report selection](dark-item-report.png)
- [Light narrow 2x report](light-item-report-narrow.png)
- [Dark narrow 2x report](dark-item-report-narrow.png)
- [Light unavailable item](light-item-report-unavailable.png)
- [Dark unavailable item](dark-item-report-unavailable.png)

## Limits

- Physical-device screen-reader, measured performance and native delivery checks
  remain outside this slice.
- Keyboard traversal uses the existing shadcn overflow menu and Vital buttons;
  no new custom focus target was added, but a dedicated keyboard activation
  check is not included here.
- The handoff-busy branch is guarded in both replacement paths but is not
  separately exercised because it requires a completed artifact with an active
  handoff.
- A foreign item is covered at the seed-validation boundary; the single-user
  store prevents creating a second owner solely for a widget fixture.
- The report period uses the current display zone. An unavailable zone is
  reported before seeding rather than guessed.
