# T03 report safety

Report link dates now use the same strict civil range parser for R01, R02 and R03. Explicit malformed, impossible, empty, equal or reversed edges cannot turn into default dates. Only absent edges use the existing display-year/current-day defaults. An unavailable device zone or current display projection blocks initialisation. Explicit representable UTC civil-year edges remain usable, including an explicit exclusive end on 9999-12-31; an inclusive manual through day of 9999-12-31 is rejected because its exclusive end is unrepresentable.

Report initialisation and Replace use the captured immutable `ReportState` as a comparison guard. A page Replace callback also captures its requested seed and route generation, so an old callback cannot apply a newly arrived URL seed. Another draft, a newly reviewed artifact, an in-flight capture/render/handoff, or a lock/reset prevents a stale seed from replacing the active state. Selecting an identical selection preserves the exact reviewed artifact. Empty controller states also receive fresh identity on creation/reset, so an approval cannot survive lock/unlock merely because both states have no selection. Controller-to-field synchronisation suppresses input listeners, and external date/name changes update the displayed fields without treating the update as a manual edit. Manual invalid input remains available for repair. The existing manual edit, preview and exact-artifact handoff pipeline is retained.

Replace remains explicit. Its complete localisable message is: “Replacing starts a new report. Private notes, source files and supporting records will be off.” The page notice and both shortcut dialogs use the same disclosure. Cancel, Escape and stale approval retain the active private choices; editing the same report keeps those choices. No private inclusion is reset by opening a link. The new key is `batch15T03ReplaceBody`; generated English localisations are included. Shared shadcn controls, colours, typography, spacing and reduced-motion behaviour remain in use.

The lead explicitly extended ownership on this task to only the two report-selection calls after their existing Replace dialogs in `lib/features/substances/substance_overview.dart` and `lib/features/events/event_pages.dart`, plus focused regression tests. Both callers now pass the original pre-dialog state to `selectIfCurrent`. The lead separately authorised switching only those two dialog body references to the new disclosure. Their route, item/event identity, existing busy/lock guards and event boundary semantics are unchanged. No router, stock, schema, dependency or shared roadmap/ticket change was made.

## Changed paths

- `lib/app/reports.dart`
- `lib/features/reports/reports_page.dart`
- `lib/features/reports/report_item_seed.dart`
- `lib/features/reports/report_dates.dart` (new)
- `lib/features/substances/substance_overview.dart` (one guarded selection call and one dialog body reference only)
- `lib/features/events/event_pages.dart` (one guarded selection call and one dialog body reference only)
- `lib/l10n/app_en.arb`, `lib/l10n/app_localizations.dart`, `lib/l10n/app_localizations_en.dart`
- `test/reports/report_dates_test.dart`, `test/reports/report_seed_safety_test.dart` (new)
- `test/reports/report_controller_test.dart`, `test/report_item_entry_test.dart`, `test/event_report_entry_test.dart`
- This evidence folder, including final captures and command logs.

## Reproduction

Before the patch, this command failed:

```sh
./tool/flutterw test --no-pub test/reports/report_seed_safety_test.dart --plain-name 'summary rejects from=2026-02-30'
```

The first selection assertion expected null but received `ReportSelection`: the impossible URL start had become the default start. This regression is now covered for every canonical template, together with empty/end/reversed/edge ranges and an appearance rebuild. Manual final-year overflow was already partly guarded in the item-era implementation; it is retained and verified through the shared parser rather than presented as a newly reproduced failure.

A final focused lock test reproduced another concrete failure before its correction: after two empty lock/reset states, selectIfCurrent returned true for an approval captured before lock/unlock because the empty const ReportState objects were canonicalised. The test lock and unlock retire an earlier seed approval failed with expected false / actual true. Fresh empty-state identity corrects that case.

## Verification

The eight-file focused regression run passed 101 checks ([regressions.log](regressions.log)). After the final requested disclosure and route-seed callback guard, the 71 affected page and shortcut checks passed ([tests.log](tests.log)). After correcting empty-state lock identity, all 13 controller checks passed ([controller.log](controller.log)). These are overlapping focused runs, not an aggregate test count. Retained logs have trailing terminal padding removed. Scoped static analysis is clean ([analysis.log](analysis.log)); the final helper documentation check is also clean ([helper-analysis.log](helper-analysis.log)). Commands:

```sh
./tool/flutterw test --no-pub --concurrency=1 --dart-define=VITAL_REPORT_SEED_CAPTURE=docs/design/reviews/2026-10-22-fifteen/T03 test/reports/report_dates_test.dart test/reports/report_seed_safety_test.dart test/reports/report_controller_test.dart test/reports/reports_page_test.dart test/report_item_entry_test.dart test/event_report_entry_test.dart test/reports/report_event_selection_test.dart test/reports/report_omission_test.dart
./tool/flutterw test --no-pub --concurrency=1 --dart-define=VITAL_REPORT_SEED_CAPTURE=docs/design/reviews/2026-10-22-fifteen/T03 test/reports/report_seed_safety_test.dart test/report_item_entry_test.dart test/event_report_entry_test.dart
./tool/flutterw test --no-pub test/reports/report_controller_test.dart
./tool/flutterw analyze --no-pub lib/app/reports.dart lib/features/reports lib/features/events/event_pages.dart lib/features/substances/substance_overview.dart test/reports/report_dates_test.dart test/reports/report_seed_safety_test.dart test/reports/report_controller_test.dart test/report_item_entry_test.dart test/event_report_entry_test.dart
```

Changed Dart files passed the pinned formatter check, and `git diff --check` passed. All six retained PNGs passed image integrity and dimension verification, and representative final light/dark captures were visually inspected. `./tool/flutterw` enforces Flutter 3.47.7 and Dart 3.13.5. No package versions were changed.

Coverage includes valid leap day, both London DST transitions (23/25-hour civil days), display-zone year rollover, years 1/9999, invalid current projection, unknown device zone, all three templates, exact item sets, private choices, a competing draft scheduled before the seed callback, stale page/shortcut Replace approval, identical reviewed selections, rendering, real pending handoff and lock/unlock retirement. Existing event boundary and report omission checks are included.

## Captures

Real Flutter widget captures use synthetic local records and bundled text/icon fonts. Recovery and replacement are checked at 320, 390 and 430 logical pixels with 2x text in light and dark themes and system reduced motion. The retained six images show each theme's invalid-date recovery at 320/2x, replacement at 390/1x and replacement at 320/2x:

- [Light recovery](light-invalid-range-narrow.png), [dark recovery](dark-invalid-range-narrow.png)
- [Light replacement](light-replacement.png), [dark replacement](dark-replacement.png)
- [Light narrow replacement](light-replacement-narrow.png), [dark narrow replacement](dark-replacement-narrow.png)

These are host widget captures, not physical-device or screen-reader acceptance. Native build/boot, physical TalkBack/VoiceOver, release gates and measured device performance remain with the lead and existing gate register. This task does not close tickets 20/21 or G04 by itself.

## Loaded skills

All paths below were directly readable and loaded; no native skill loader was required and no skill-file access failed:

- `/home/mike/.codex/skills/flutter-expert/SKILL.md`
- `/home/mike/.codex/skills/flutter-expert/references/riverpod-state.md`
- `/home/mike/.codex/skills/flutter-expert/references/gorouter-navigation.md`
- `/home/mike/.codex/skills/flutter-expert/references/widget-patterns.md`
- `/home/mike/.codex/skills/flutter-expert/references/project-structure.md`
- `/home/mike/.codex/skills/flutter-expert/references/performance.md`
- `/home/mike/.codex/skills/codebase-memory/SKILL.md`
- `/home/mike/.codex/skills/verification-before-completion/SKILL.md`
- `/home/mike/.codex/skills/dart-add-unit-test/SKILL.md`
- `/home/mike/.codex/skills/dart-run-static-analysis/SKILL.md`
- `/home/mike/.codex/skills/dart-write-documentation/SKILL.md`
- `/home/mike/.codex/skills/flutter-add-widget-test/SKILL.md`
- `/home/mike/.codex/skills/flutter-apply-architecture-best-practices/SKILL.md`
- `/home/mike/.codex/skills/flutter-build-responsive-layout/SKILL.md`
- `/home/mike/.codex/skills/accessibility-compliance/SKILL.md`
- `/home/mike/.codex/skills/debugging-wizard/SKILL.md`
- `/home/mike/Development/true_grit_vital/.agents/skills/vital-mobile-copy/SKILL.md`
- `/home/mike/.codex/skills/better-writing/SKILL.md`
- `/home/mike/.codex/skills/interaction-design/SKILL.md`
- `/home/mike/.codex/skills/ui-ux-pro-max/SKILL.md`
- `/home/mike/.codex/skills/ui-ux-pro-max/references/pro-rules.md`
- `/home/mike/.codex/skills/ui-ux-pro-max/references/quick-reference.md` (relevant accessibility, interaction and performance sections)

The parent checkout supplied the required ignored `AGENTS.md`, implementation README, T03 assignment/contract, original tickets 20/21, specification README/plan/content contract, engineering policy, interaction blueprint/implementation row, component catalogue and D20 roadmap context. None was rewritten.

## API and graph evidence

The graph was queried at Tier 2 against parent project `home-mike-Development-true_grit_vital`, with both-direction `_ReportsPageState` tracing and snippets followed by direct source reads. Core coverage reported generation `2026-10-22T22:17:00Z`; supplemental paths were checked at `2026-10-22T22:31:25Z`, with best-effort `metadata_match` for existing evidence paths; the report facade has a partial parse and new worktree files are absent as expected. Those paths were read directly. No absence/completeness claim is made and the parent graph was not reindexed into this worktree.

Primary documentation checked: [Dart date parsing](https://api.dart.dev/dart-core/DateTime/parse.html), [Flutter post-frame callbacks](https://api.flutter.dev/flutter/widgets/WidgetsBinding/addPostFrameCallback.html) and [Riverpod refs/lifecycle](https://riverpod.dev/docs/concepts2/refs). The relevant scheduling/lifecycle signatures were also inspected in the pinned Flutter scheduler source and installed Riverpod 3.4.3 `lib/src/core/ref.dart`. The implementation uses the project's strict `CivilDate.parse`, not normalising `DateTime.parse`.

Task-owned test build output and Flutter hook/build caches were removed after verification. Package configuration, installed SDK/package dependencies and all final source/evidence files were retained.
