# D11a saved schedule instructions

Status: integrated locally after lead review. Physical-device gates remain open.

## Capability

One optional authored text field is saved with each immutable daily plan version. It is
separate from the existing D08 substance instructions and from generated requirements.
The field accepts multiple lines, preserves the exact entered text and is bounded at 4000
characters. Empty text is omitted from the additive JSON payload so frozen legacy command
shapes and retries keep their earlier shape.

The schedule editor, preview review and shared plan summaries display the saved text. A
compact substance summary shows only a presence badge; the detailed summary shows the text.
The history and resolved expectation records do not copy it, so historical occurrences do
not gain a current note retroactively and reminder-facing expectation JSON stays free of it.

Saves use the existing command, revision, generation, lock, draft and restore guards.
Version copies for ordinary edits, pause/restart, phases and resolver-internal timing carry
the text. A changed value creates a new audit version; earlier audit snapshots are retained.

## Files

- `lib/domain/scheduling/daily_plan.dart`
- `lib/data/daily_codec.dart`
- `lib/data/daily_store.dart`
- `lib/data/pause_store.dart`
- `lib/domain/scheduling/daily_resolver.dart`
- `lib/domain/scheduling/phase_plan.dart`
- `lib/domain/drafts/ordinary_draft.dart`
- `lib/features/plans/plan_form.dart`
- `lib/features/plans/pause_editor.dart`
- `lib/features/plans/phase_editor.dart`
- `lib/features/plans/today_plan_rows.dart`
- `lib/features/substances/substance_summary.dart`
- `lib/features/substances/substance_overview.dart`
- `lib/l10n/app_en.arb` and regenerated localisations
- `test/data/plan_instructions_test.dart`
- `test/plan_instructions_ui_test.dart`
- `test/screen_schedule_capture_test.dart`
- `test/screen_schedule_support.dart`
- `test/design_substance_summary_fixture.dart`

No SQL schema change was made. No report, template, export, notification or roadmap file
was edited.

## Copy review

- Section heading: `Plan instructions` (two words).
- Field label: `Instructions`; helper: `Your own wording for this plan. It stays private.`
- Bound error: `Keep plan instructions within 4000 characters.`
- The existing one-word `Save`, `Preview`, `Discard` and `Retry` commands are unchanged.
- The field is multiline and the helper follows the surrounding sentence-case style.

## Verification

Commands were run from this worktree with `./tool/flutterw`.

- `analyze`: `No issues found!`
- `test/data/plan_instructions_test.dart`: 9 passed. Covers legacy JSON/default shape,
  multiline exactness, encrypted restart, backup snapshot restore, expectation exclusion,
  retry idempotency, stale revision, immutable audit versions, pause/phase copies and the
  exact bound.
- `test/plan_instructions_ui_test.dart`: 6 passed. Covers saved editor text, draft restore,
  clear-and-save, overview summary, shared compact/detailed summary, over-limit validation,
  320 px at 2x text, light/dark and reduced motion.
- `test/screen_schedule_editor_test.dart`, `test/screen_schedule_layout_test.dart`: 27 passed.
- `test/data/daily_store_test.dart`, `test/data/phase_store_test.dart`: included in a
  66-test combined focused run, all passed.
- `test/data/pause_store_test.dart`, `test/pause_ui_test.dart`, `test/phase_ui_test.dart`:
  33 passed.
- `test/data/interval_store_test.dart`, `test/data/chart_phase_end_context_test.dart`:
  18 passed.
- `test/screen_schedule_capture_test.dart` with `--dart-define
  VITAL_SCHEDULE_CAPTURES=<this directory>`: 2 passed. Captures show the instructions
  section with exact multiline text in light and dark themes.

## Captures

- `light-schedule-full.png` and `dark-schedule-full.png` show the complete editor.
- `light-schedule.png` and `dark-schedule.png` show the viewport composition.

## Fixture review

`test/design_substance_summary_test.dart` timed out after ten minutes in the focused
regression run on `the streamed container page stays disclosed at its bound` and then
cascaded into the following test. The same test was rerun alone with the same timeout.
A bounded stash baseline check was attempted, but the command did not complete inside its
shell bound; the task stash was restored and all modified and new files were verified
present. No baseline result was obtained. The instruction path is not exercised by that
test, and the new summary branches are no-ops when no plan exists. This is reported for
lead review. The lead corrected the fixture teardown to dispose watched providers before
awaiting database close, using the existing widget-aware IO drain. The fixture also awaits
mounting its widget. The formerly hanging 51-container test then passed in two seconds;
the complete 14-test substance-summary suite passed in fourteen seconds. No production
stream behavior or collection limit was weakened to satisfy the test. The original worker
did not establish a baseline result, so this review makes no baseline-failure claim.

Lead integration also passed 118 instruction, daily/pause/phase/interval store,
draft/UI and schedule-capture checks with clean project analysis. Constructor
copy sites were checked against graph callers and exact source. No public
report/export or notification field gained the private authored text.

## Report/export seam

No report or export change is included. Current export/report models carry item-level
authored instructions, not plan-version instructions. If plan instructions must appear in
generated outputs, the lead should add the saved plan text to the export/report builder
only when the existing `notesIncluded` consent is true; the private text must not enter a
notification payload or an always-included public field.

## Skills read

- `/home/mike/.codex/skills/flutter-expert/SKILL.md`
- `/home/mike/.codex/skills/flutter-expert/references/riverpod-state.md`
- `/home/mike/.codex/skills/flutter-expert/references/widget-patterns.md`
- `/home/mike/.codex/skills/codebase-memory/SKILL.md`
- `/home/mike/.codex/skills/flutter-apply-architecture-best-practices/SKILL.md`
- `/home/mike/.codex/skills/dart-add-unit-test/SKILL.md`
- `/home/mike/.codex/skills/flutter-add-widget-test/SKILL.md`
- `/home/mike/.codex/skills/flutter-build-responsive-layout/SKILL.md`
- `/home/mike/.codex/skills/ui-ux-pro-max/SKILL.md`
- `/home/mike/.codex/skills/dart-run-static-analysis/SKILL.md`
- `/home/mike/.codex/skills/better-writing/SKILL.md`
- `/home/mike/.codex/skills/verification-before-completion/SKILL.md`
- `/home/mike/Development/true_grit_vital/.agents/skills/vital-mobile-copy/SKILL.md`
  (worktree `.agents` is not copied; read from the root checkout)

## Graph evidence

Used codebase-memory project `home-mike-Development-true_grit_vital`, indexed
`2026-10-22T01:55:18Z`, Tier 2. `search_graph` confirmed the `DailyPlanVersion` class and
the schedule/summary classes. `check_index_coverage` returned `no_recorded_issue` with a
best-effort caveat for every evidence path; private Dart call edges were followed in exact
source, including all `DailyPlanVersion` constructor copies.
