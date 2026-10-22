# Exact date jump

## Lead integration

The lead guarded delayed confirmation against lock and zone changes, made the
shown zone follow the existing day-bound fallback and rejected 9999-12-31,
whose exclusive next-day bound cannot be represented by the current domain.
Validation names the supported range. Eleven final date-jump/capture checks
passed, including earliest-date fallback, leap dates, cancellation, zone changes,
lock and both themes. The final History mobile/page run passed 19 checks.
An earlier combined run had one 52 px scroll-offset mismatch; that case passed
alone and in the final two-file run. No assertion was weakened.

D19c adds a compact `Date` command beside the History calendar filters. It opens
a short shared dialog with a visible, persistent `Date` label, strict
`YYYY-MM-DD` entry and one-word `Go` confirmation. `Cancel`, Escape and system
Back return no date, so the selected day, month, filters and records stay
unchanged. Focus returns to the `Date` command.

Confirming a real date updates the visible calendar month and selected date
together with the existing zone-based day bounds. Type, event, status, item and
unit filters stay selected, and report/export return links carry the new month
and selected date. The dialog never reads, writes or corrects a record. Today,
month arrows, swipes, calendar/list switching and the existing filter range
remain available. A privacy lock closes an open dialog before a date can be
confirmed.

## Copy

- Command: `Date`
- Heading and accessible name: `Go to date`
- Field label: `Date`
- Helper: `Use YYYY-MM-DD. The day uses {zone}.`
- Validation: `Enter a real date as YYYY-MM-DD.`
- Commands: `Go`, `Cancel`

All strings live in `lib/l10n/app_en.arb` with descriptions and the helper's
zone placeholder metadata. Generated localisations were regenerated.

## Verification

- `./tool/flutterw test --no-pub test/history_date_jump_test.dart`: 8 checks
  passed. Covers distant year, leap day, malformed/impossible/out-of-range
  values, spring and autumn DST bounds, filters and item/unit scope, report
  return context, Today, Cancel/Escape/Back, keyboard confirmation, focus,
  privacy lock and 320 px at double text in both themes.
- Existing History and motion regressions:
  `history_mobile_ui_test.dart`, `screen_history_pages_test.dart`,
  `history_week_summary_test.dart`, `history_routine_activity_test.dart`,
  `motion_standards_test.dart`: 54 checks passed.
- Shared framework: `visual_framework_test.dart`, `design_system_test.dart`,
  `screen_history_week_capture_test.dart`: 45 checks passed.
- `./tool/flutterw analyze`: no issues found.

Counts overlap and are not a unique suite total. No physical-device
screen-reader, keyboard or performance acceptance is claimed.

## Captures

Synthetic records on the canonical `/history` route, with the real fixed dock
and device safe insets.

- [Light](light-history-date-jump.png)
- [Dark](dark-history-date-jump.png)
- [Dark, 320 px and double text](dark-history-date-jump-narrow-double-text.png)

## Skills and standards read

Read directly before editing:

- `/home/mike/.codex/skills/flutter-expert/SKILL.md`
- `/home/mike/.codex/skills/codebase-memory/SKILL.md`
- `/home/mike/Development/true_grit_vital/.agents/skills/vital-mobile-copy/SKILL.md`
- `/home/mike/.codex/skills/better-writing/SKILL.md`
- `/home/mike/.codex/skills/flutter-add-widget-test/SKILL.md`
- `/home/mike/.codex/skills/flutter-build-responsive-layout/SKILL.md`
- `/home/mike/.codex/skills/dart-add-unit-test/SKILL.md`
- `/home/mike/.codex/skills/dart-run-static-analysis/SKILL.md`
- `/home/mike/.codex/skills/interaction-design/SKILL.md`
- `/home/mike/.codex/skills/ui-ux-pro-max/SKILL.md`
- `/home/mike/.codex/skills/verification-before-completion/SKILL.md`
- `/home/mike/Development/true_grit_vital/AGENTS.md`
- `/home/mike/Development/true_grit_vital/docs/specification/README.md`
- `/home/mike/Development/true_grit_vital/docs/specification/content-and-interaction.md`
- `/home/mike/Development/true_grit_vital/docs/discovery/engineering-skills-and-quality.md`
- `docs/design/interaction-blueprint.md`
- `docs/design/interaction-implementation-plan.md` (History row)
- `docs/design/components.md`
- `docs/design/roadmap.md`

The ignored specification documents were absent from the worktree and were
read from the parent checkout as instructed.

## Limits

Timing-tolerance classification, adherence inference, report definitions and
physical-device accessibility remain open. The jump changes only the browsed
date and existing query bounds; it does not create, edit, backdate or correct
any record. Measurements use real daylight-saving dates through the existing
display clock.
