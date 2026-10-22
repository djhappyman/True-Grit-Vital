# Event report entry

22 October 2026, D16c. Based on `2b283a5`. No dependency, schema or History
change. The canonical Reports page and report controller remain the only report
selection and generation path.

## Behaviour

- `Event detail` now has one-word `Report` action beside the existing event
  actions. Its accessible name includes the full event name.
- The action seeds the existing Reports selection with template `R03` (Event
  review), the exact event ID, an explicit half-open date range and the current
  display zone. No second report screen or generator exists.
- Start uses the event's actual start when recorded, otherwise its planned
  start. End uses the actual end, or the completion instant for a completed
  event. A planned end is never treated as an actual end.
- A date-only end includes its whole day in the event zone. Timed boundaries
  stay exact and are projected into the report's display zone. The event zone
  and report period are both visible in the selected-event review.
- An ongoing event with no recorded end is seeded through the current display
  day and shows `No event end is recorded.` It does not invent an event end.
- An unresolved start, an unresolved completed end or an unavailable zone
  disables the action with visible explanation. The action is never enabled
  with a fabricated range.
- Opening Report while another report selection is active shows a short
  `Replace report?` decision. `Cancel` preserves the active selection and its
  state. `Replace` selects the event report and clears any previous preview
  artifact. A busy report cannot be replaced and is identified explicitly.
- A direct event report link that meets an active selection shows the same
  protection inside Reports, with a `Replace` action. It does not silently
  overwrite the active draft.
- The header `Back` action and platform Back return to the same event.
- The app lock continues to cover the event detail page and the canonical
  report editor; the action is not reachable while locked, and generation keeps
  its existing lock guard.

## Verification

- `./tool/flutterw test --no-pub test/event_report_entry_test.dart`
  passed 19 checks: inclusive date-only end, exact-zone projection, DST,
  missing and partial starts, completed event without end, ongoing range,
  unavailable zone, coverage, named selection, Back, app lock, pending
  selection preservation and replacement, direct-link protection, both themes
  at 320 px and 2x text, and capture isolation.
- `./tool/flutterw test --no-pub test/reports/reports_page_test.dart
  test/reports/report_event_selection_test.dart test/screen_events_page_test.dart`
  passed 20 checks.
- `./tool/flutterw test --no-pub test/event_ui_test.dart` passed 26 checks.
- `./tool/flutterw test --no-pub test/reports/report_controller_test.dart`
  passed 9 checks.
- `./tool/flutterw analyze` reported no issues.

## Captures

Synthetic records only, captured with:

```
./tool/flutterw test --no-pub test/event_report_entry_test.dart \
  --plain-name "event report captures use synthetic records" \
  --dart-define=VITAL_EVENT_REPORT_CAPTURE=/tmp/opencode/event-report-capture
```

- [Light event action](light-event-report-action.png)
- [Dark event action](dark-event-report-action.png)
- [Light report selection](light-event-report.png)
- [Dark report selection](dark-event-report.png)
- [Light narrow 2x report](light-event-report-narrow.png)
- [Dark narrow 2x report](dark-event-report-narrow.png)
- [Light unavailable action](light-event-report-disabled.png)
- [Dark unavailable action](dark-event-report-disabled.png)

## Limits

- The report keeps the current device display zone for its period and times;
  the event's own zone drives boundary resolution and is shown in the review.
  A zone different from the event zone is therefore reviewable but not
  silently substituted.
- An ongoing event report covers recorded entries to the current day only. It
  is labelled as missing an event end and does not claim a complete course.
- Physical-device screen-reader, measured performance and native delivery
  checks remain outside this slice.
