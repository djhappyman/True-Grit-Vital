# Stock movement source inspection

Slice D13h, 22 October 2026. The read-only history under a stock adjustment now
offers `Open` only when a movement names a real recorded-use record. The command
opens the canonical `HistorySourcePage` through the existing router. It never
writes stock and never treats a correction's movement identity as a record.

## Behaviour

- `Record dose` movements with `recordId` show one compact `Open` command. The
  visible label is one word; its accessible name is `Open recorded dose`.
- Restock, waste, measure, reconciliation and correction movements show no
  source command. A correction links through `reversesId` only as movement
  identity, so it cannot fabricate a record link.
- A combined dose is resolved to the canonical combined History entry. Each
  component movement opens the same group rather than a single component.
- The source route keeps immutable person and record identity. The path and
  query are built with `Uri` and `Uri.encodeComponent`, not raw concatenation.
- The `return` value is the current stock surface, so Back returns to the same
  adjustment history and then to the retained inventory search state.
- Inspection reads the record's current version. A corrected dose shows its
  current amount and `Recorded`; a voided dose shows `Voided`. The movement's
  historical amount is not presented as the saved record's current version.
- A record that no longer resolves uses the canonical `Source` missing state.
- App lock hides the source and movement content immediately; unlocking returns
  to the same read-only source.
- There are no stock mutations and no schema, provider, domain or store edits.

## Copy

| Location | Visible | Accessible |
| --- | --- | --- |
| Stock history, recorded-use movement | `Open` | `Open recorded dose` |

The new ARB entries are `stockMovementOpen` and `stockMovementOpenSource`. The
heading `Stock history` and the canonical `Source` heading are unchanged. No em
or en dash is used.

## Evidence

Commands run from the worktree root:

- `./tool/flutterw test --no-pub test/stock_movement_source_test.dart`: 11
  tests passed.
- `./tool/flutterw test --no-pub test/stock_ui_test.dart test/stock_surface_route_switch_test.dart`:
  13 tests passed.
- `./tool/flutterw test --no-pub test/history_mobile_ui_test.dart`: 10 tests
  passed.
- `./tool/flutterw analyze`: no issues found.
- Capture run:
  `./tool/flutterw test --no-pub test/stock_movement_source_test.dart --dart-define=VITAL_STOCK_SOURCE_CAPTURES=docs/design/reviews/2026-10-22-third-five/stock-source`
  passed all 11 tests and wrote eight synthetic Flutter captures.

The focused checks cover:

- actual, corrected and voided dose inspection;
- combined-group identity;
- absent source commands for restock, waste, measure and correction;
- correction `recordId` null and `reversesId` kept as movement identity;
- encoded path segments matching the current router, including a reserved
  character identity;
- missing-record canonical state and lock/unlock;
- keyboard focus with Enter activation, then Back;
- page-two retention after source inspection;
- retained inventory search after nested dismissal;
- 320, 390 and 430 px widths at double text in light and dark, with reduced
  motion for the narrow runs.

## Captures

All images show synthetic records only.

- `light-history.png`, `dark-history.png`: 390 px stock history with the one
  `Open` command beside the recorded-use row.
- `light-source.png`, `dark-source.png`: canonical `Source` page after
  inspection, showing the corrected current amount and `Recorded` state.
- `light-history-320x2.png`, `dark-history-320x2.png`: 320 px at double text.
  The history is scrolled to the movement row, so earlier sheet content sits
  above the viewport.
- `light-source-320x2.png`, `dark-source-320x2.png`: 320 px at double text,
  with full long identity, status, dates and exact units readable.

## Limits

- The missing-record case uses the canonical route directly because the current
  app has no record-deletion command that can leave a real orphan movement.
- Lead integration fault-injected a delayed source lookup failure and verified
  the saved-record fallback. The destination's own missing/error states remain
  authoritative.
- Captures are Flutter widget surfaces. No physical-device screen reader,
  switch access or native paging check was run in this slice.
- The 430 px state is covered by the widget test but is not separately captured.

## Skills and documents read

Skill files:

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
- `/home/mike/.codex/skills/verification-before-completion/SKILL.md`

Project documents:

- `/home/mike/Development/true_grit_vital/AGENTS.md`
- `/home/mike/Development/true_grit_vital/docs/specification/README.md`
- `/home/mike/Development/true_grit_vital/docs/specification/content-and-interaction.md`
- `/home/mike/Development/true_grit_vital/docs/discovery/engineering-skills-and-quality.md`
- `/home/mike/Development/true_grit_vital/docs/design/interaction-blueprint.md`
- `/home/mike/Development/true_grit_vital/docs/design/interaction-implementation-plan.md`
- `/home/mike/Development/true_grit_vital/docs/design/components.md`
- `/home/mike/Development/true_grit_vital/docs/design/roadmap.md`

Flutter primary guidance checked: <https://docs.flutter.dev/ui/accessibility>
and <https://docs.flutter.dev/cookbook/testing/widget/introduction>.

Graph coverage was checked in the parent project
`home-mike-Development-true_grit_vital` (ready generation
`2026-10-22T20:20:58Z`, newer than the packet generation). The cited stock,
history, router, store, recording and localisation command paths reported
`no_recorded_issue` with metadata match. `lib/l10n/app_en.arb` is not tracked by
the code graph, so it was read directly. A clean signal is not proof of
completeness; the touched files and uncovered ARB were read as source.

## Lead integration

The lead inspected light/dark and narrow captures and added explicit guards for
an outstanding source lookup. Open is disabled during that task; navigation is
cancelled after a lock-state change or when the originating route is no longer
current. Repeated activation cannot stack duplicate source pages. The captured
return location is kept stable throughout the lookup.

Five deferred-provider checks cover lock, lock then unlock, duplicate activation,
leaving the page and lookup failure with the saved-record fallback. They use the
real stock-history widget and router with synthetic delayed reads. The existing
canonical missing/error/locked-source tests remain separate evidence.

An integration run caught continuous loading animation underneath the source
sheet; the spinner now stops when lookup finishes while the duplicate-navigation
guard remains until Back. Final successful commands are recorded below.

Final lead verification: 16 source/deferred-provider checks passed after the
spinner correction; 23 unchanged stock/history regression cases passed in the
earlier mixed run that exposed the spinner failure. Final whole-project analysis
was clean. The earlier mixed run itself failed and is retained as diagnostics.
