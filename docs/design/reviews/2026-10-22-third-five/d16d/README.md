# D16d/D19 event History entry

Scope: open the canonical History destination from the existing event detail
history summary with the exact event filter and the single-user scope. The
event preview remains in place and is not duplicated. No record, event or stock
data is written.

## Behaviour

- The event detail History section keeps its existing `EventActualList` preview.
- A one-word `Open` command sits beside the History heading. Its accessible name
  is `Open History for {event name}`.
- The destination is `/history` with `scope=me`, one exact `event` value and a
  local `return` value. No `from`, `before`, `type`, `status`, `item`, `unit` or
  `anchor` restriction is added from the event's planned dates.
- The History destination shows the full event name in a compact filter chip
  before the calendar, so the scope is visible on arrival. If the event no
  longer resolves, the chip says `Event unavailable` instead of inventing a
  name or widening the filter.
- Existing History status controls remain authoritative for recorded, skipped
  and voided entries. Voided entries are not added to the event preview.
- A visible `Back` command and system Back return to the same event through a
  validated local return path. The return path is also retained when History
  navigates to a source record and back.
- When a retained root History page receives a new event seed in place, the
  previous type/event/status/date filter state, filter labels, date field text
  and browsing position are cleared before the new window is configured. Earlier
  filters therefore do not leak into the event view.
- Missing event IDs still show the existing unavailable detail state. An app
  lock hides the event detail and the History command; unlocking restores it.

## Files

Changed:

- `lib/features/events/event_pages.dart` — adds the History heading command,
  accessible name and lock guard; keeps `EventActualList`.
- `lib/features/history/history_pages.dart` — accepts and validates the return
  seed, clears retained filter state on a new seed, shows the event scope chip,
  and provides the visible/system Back path. This was necessary because History
  is a retained root destination: pushing another instance of the same branch
  page produces duplicate page keys, and the root must accept the seed in place
  without leaking old filters. The page also had no visible return command.
- `lib/l10n/app_en.arb` plus generated `lib/l10n/app_localizations*.dart` —
  three complete localisable strings with placeholder metadata.

Added:

- `lib/features/events/event_history_location.dart` — exact event/scope URL and
  optional validated local return path.
- `test/event_history_entry_test.dart` — 12 focused location, navigation,
  isolation, paging, filter, lock, keyboard, Back, narrow-text and capture
  checks.

No reports, router, substance, stock, schema or dependency files were edited.
No data writes or new screens were introduced.

## Skills actually loaded

- `/home/mike/.codex/skills/flutter-expert/SKILL.md`
- `/home/mike/.codex/skills/flutter-expert/references/gorouter-navigation.md`
- `/home/mike/.codex/skills/flutter-expert/references/widget-patterns.md`
- `/home/mike/.codex/skills/codebase-memory/SKILL.md`
- `/home/mike/Development/true_grit_vital/.agents/skills/vital-mobile-copy/SKILL.md`
- `/home/mike/.codex/skills/better-writing/SKILL.md`
- `/home/mike/.codex/skills/dart-add-unit-test/SKILL.md`
- `/home/mike/.codex/skills/flutter-add-widget-test/SKILL.md`
- `/home/mike/.codex/skills/flutter-build-responsive-layout/SKILL.md`
- `/home/mike/.codex/skills/dart-run-static-analysis/SKILL.md`
- `/home/mike/.codex/skills/interaction-design/SKILL.md`
- `/home/mike/.codex/skills/ui-ux-pro-max/SKILL.md`
- `/home/mike/.codex/skills/ui-ux-pro-max/references/pro-rules.md`
- `/home/mike/.codex/skills/verification-before-completion/SKILL.md`

## Documents actually loaded

- `/home/mike/Development/true_grit_vital/AGENTS.md`
- `/home/mike/Development/true_grit_vital/docs/specification/README.md`
- `/home/mike/Development/true_grit_vital/docs/specification/content-and-interaction.md`
- `/home/mike/Development/true_grit_vital/docs/discovery/engineering-skills-and-quality.md`
- `/home/mike/Development/true_grit_vital/docs/design/interaction-blueprint.md`
- `/home/mike/Development/true_grit_vital/docs/design/interaction-implementation-plan.md`
- `/home/mike/Development/true_grit_vital/docs/design/components.md`
- `/home/mike/Development/true_grit_vital/docs/design/roadmap.md`
- `/home/mike/Development/true_grit_vital/.scratch/vital-implementation/third-five-2026-10-22/contract.md`

Primary documentation checked: `https://docs.flutter.dev/ui/accessibility` and
`https://docs.flutter.dev/cookbook/testing/widget/introduction`. The pinned
Flutter 3.47.7 SDK source for `PopScope` and the pinned go_router 18.1.0
route-match source were checked for the Back and page-key behaviour.

## Graph evidence

- Project: `home-mike-Development-true_grit_vital`, root parent checkout.
- Latest checked generation: `2026-10-22T20:54:58Z`, status ready.
- `check_index_coverage` reported no recorded issue for the existing evidence
  files: `event_pages.dart`, `history_pages.dart`, `app/history.dart`,
  `app/vital_app.dart`, `data/history_store.dart`.
- `app_en.arb` is not tracked by the code graph and was read directly. The new
  helper and test are missing from the parent generation and were read directly
  from the worktree, as were the ranges used for the changes.

## Verification

Commands run from the worktree:

```text
./tool/flutterw analyze
# No issues found

./tool/flutterw test --no-pub test/event_history_entry_test.dart
# 12 passed

./tool/flutterw test --no-pub test/event_collection_capture_test.dart \
  test/event_collection_store_test.dart test/event_collection_ui_test.dart \
  test/event_history_entry_test.dart test/event_report_entry_test.dart \
  test/event_summary_ui_test.dart test/event_ui_test.dart \
  test/history_date_jump_test.dart test/history_mobile_ui_test.dart \
  test/history_moved_anchor_test.dart test/history_routine_activity_test.dart \
  test/history_splice_race_test.dart test/history_week_summary_test.dart \
  test/screen_events_capture_test.dart test/screen_events_page_test.dart
# 154 passed
```

The focused test file covers:

- exact scope/event/return encoding and absence of date filters;
- explicit membership entries outside the planned dates but inside the saved
  actual boundaries;
- event A/B isolation and exact paging past 50 linked entries (25/50/52);
- recorded, skipped and voided status controls;
- an event with no linked records keeps the existing empty History state and
  does not broaden to unrelated records;
- a retained root History filter before the event seed, and Back to the event;
- missing and locked events;
- keyboard focus and Enter activation, plus system Back;
- 320 px at 2x text in light and dark with no render exception and the full
  event name retained;
- synthetic light/dark captures.

## Captures

Generated with:

```text
./tool/flutterw test --no-pub test/event_history_entry_test.dart \
  --plain-name "event History captures" \
  --dart-define=VITAL_EVENT_HISTORY_CAPTURE=docs/design/reviews/2026-10-22-third-five/d16d/captures
```

- `captures/light-event-history-command.png`
- `captures/light-event-history-command-narrow.png`
- `captures/light-event-history.png`
- `captures/light-event-history-narrow.png`
- `captures/dark-event-history-command.png`
- `captures/dark-event-history-command-narrow.png`
- `captures/dark-event-history.png`
- `captures/dark-event-history-narrow.png`

All records, names, quantities and dates in the captures are synthetic.

## Limitations

- The existing History event filter still applies the saved
  `event_history_bounds` (actual start/end, falling back to planned dates). This
  slice adds no date restriction of its own and does not change
  `lib/data/history_store.dart`, which is outside its ownership. A record
  explicitly linked by membership but outside those saved bounds is therefore
  not shown by the existing filter. The focused test proves records outside the
  planned dates but inside the recorded actual dates are included.
- Navigation uses `go` to the retained History root because pushing a second
  instance of the same shell branch page produced duplicate page keys. Back
  returns to the same event through the local return seed, but a prior Events
  list stack is not restored beneath that event.
- The existing multi-event URL encoding is comma-separated. Generated event IDs
  are UUIDs; an ID containing a comma would not round-trip through that existing
  format. Query-reserved characters, spaces and non-ASCII values are encoded.
- The event scope chip adds one event-name lookup when the page is entered with
  a single seeded event. It does not add count queries or writes.
- Host Flutter tests and synthetic captures only. No physical-device screen
  reader, native build, measured performance or device-back evidence is claimed.
- The existing EventDetail and History loading/error presentations were not
  re-simulated with a forced database failure; those paths are unchanged by this
  slice. Missing, empty, locked, filtered, paged and Back states are covered.
