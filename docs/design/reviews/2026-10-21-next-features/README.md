# Next feature batch

D08 and D10 use OpenCode’s `opencode/deepseek-v4.1-flash-free` in isolated worktrees. The lead owns D20 and integration review. All three packages are host integrated and verified after lead review.

## D08: Substance setup

- Saving identity creates no schedule, dose or stock. A durable Setup marker offers optional Schedule, Stock and Details steps. The existing editors retain their previews, drafts and commands, and now return to Setup after save. Cancel preserves the committed identity and progress; the overview offers Continue.
- Instructions and private notes preserve authored text, quantities and units. Revisions prevent stale overwrites, operation IDs prevent duplicate saves, and drafts survive leaving the editor. Notes and instructions enter reports and structured exports only when notes are selected. Encrypted backup preparation preserves details and retires local setup progress.
- Review added explicit captured-generation checks to setup/detail commands, retired progress from a previous dataset instead of reviving its skipped choices, corrected stale detail-revision comparison, and restored Retry for schedule reads.
- Schema 22 adds details/setup; schema 23 adds dose context. Fresh databases apply both migrations; dedicated 21-to-23 and 22-to-23 checks preserve rows and drafts. Review also found the backup service still capped validation at schema 21. Backup/restore now use the record store’s shared schema constant. The existing encrypted archive creation/validation test reproduced the unsupported-version failure before the fix.

| View | Light | Dark |
| --- | --- | --- |
| Optional setup | [Image](light-substance-setup.png) | [Image](dark-substance-setup.png) |
| Authored details | [Image](light-substance-details.png) | [Image](dark-substance-details.png) |

The final setup group passed 22 store, migration, restore, UI and visual checks. It includes canonical schedule/stock return paths, cancellation/drafts, generation and revision rejection, encrypted detail preservation, both themes and 320 px at double text. The combined Settings, create, recording and export group passed 39 checks; report text/PDF/template capture passed 15; the backup service passed all eight checks after the schema fix. Static analysis is clean. Screenshots use real fonts at 390×844 with top/bottom device insets. Light/dark setup and detail captures were inspected. These are host checks, with no new platform build or physical-device claim.

D08’s initial task activity confirms reads of all ten requested skill files before edits, including Flutter expert, graph, architecture, unit/widget tests, responsive layout, UI guidance, analysis, better writing and the repository copy skill. The worker’s final summary had lost this evidence; the lead checked the durable activity rather than treating the summary as the access record.

## D10: Dose context

- Optional notes and neutral context tags live behind More. Empty context remains valid, quick Taken is unchanged, and no label or schedule generates instructions. Saved revisions retain context; an explicit clear creates the intended new revision. Old correction drafts without context fields preserve existing text instead of erasing it.
- Skip reasons use a compact secondary disclosure. Skip and Undo preserve the saved action identity and never create a dose or stock movement. Source/action history retains the reason.
- Structured JSON exports contain a separate `skipped` collection. CSV uses `record_type=skip` and appended skip columns, with no dose quantity or revision invented for the action. Skips share the existing doses content selection, are counted separately in Preview and fail truthfully at the explicit 5,000-action bound. Current undone skips are excluded from the current timeline export; the full encrypted archive retains the stored records.
- Private substance instructions, notes, dose notes and skip reasons remain excluded unless notes are deliberately selected. Review corrected the old supporting-only toggle descriptions in reports and exports. Neutral dose tags remain structured metadata. R02 detailed history carries skip reasons in text and PDF; R03 keeps its existing event counts rather than adding a second detailed ledger.
- Lead integration verified the real production sequence: password-encrypted archive creation, validation, database preparation, activation, reopening and private/shared export. Both dose revisions, notes, tags and the saved skip reason survive. The test initially assumed one exported dose row; review corrected it to assert both saved revisions. The parent’s shared schema fix resolves the worker checkout’s archive-version rejection.
- Empty-context record commands retain the legacy payload shape, so a committed command from an older database replays instead of conflicting. Changed context still fails command-payload reuse.

The final combined D10 run passed **89 focused checks**, including store/export bounds and CSV alignment, report text/PDF, record and correction UI, encrypted restore, archive activation and export preview/privacy. Static analysis is clean. The expanded More fields also receive the 320/390/430 px check at normal and double text. No whole-suite run, new platform build, native performance measurement or new release is claimed.

The repair worker reports actual reads of Flutter expert and its Riverpod/widget references; graph, architecture, unit/widget testing, responsive layout, UI guidance, static analysis and better-writing skills; and the root repository copy skill. It kept the parent-owned backup fix separate and reported its blocked restore test honestly instead of bypassing validation.

## D20: Settings data

- The Data tab reads whole-collection substance, current non-voided dose/supporting-record and ready-file counts. Corrections/revisions are not extra doses. Physical size measures this store’s database and current WAL/shared-memory files, without a directory scan or reading file contents. Unavailable size stays unavailable; exported files and backup archives are outside the measurement.
- Counts refresh from committed record/draft changes. App lock hides them immediately and dataset replacement retires the old subscription. Failed reads offer Retry.
- 30-day, 90-day and year-to-date shortcuts show exact inclusive civil dates, then open the existing report selection. Notes/attachments remain off by default. Back returns to the Data tab.
- The shared tab strip keeps the selected choice visible at large text without scrolling an outer page. Existing containers, typography, shadcn controls and motion remain shared. No dependencies or schema changes were added for D20.

| View | Light | Dark |
| --- | --- | --- |
| Data summary | [Image](light-settings-data.png) | [Image](dark-settings-data.png) |
| Report dates | [Image](light-report-shortcuts.png) | [Image](dark-report-shortcuts.png) |
| 320 px, double text | [Image](light-report-shortcuts-narrow.png) | [Image](dark-report-shortcuts-narrow.png) |

Six store/unit checks and five new UI checks passed, including full collection counts, correction/void semantics, ready/deleted files, live updates, lock privacy, read recovery, report date bounds/return context, both themes and narrow double text. Static analysis is clean. The final combined run passed all 56 Settings/design/store checks. These are host checks, with no physical-device or performance claim.

Skills actually read: `/home/mike/.codex/skills/flutter-expert/SKILL.md`, `codebase-memory/SKILL.md`, `flutter-apply-architecture-best-practices/SKILL.md`, `dart-add-unit-test/SKILL.md`, `flutter-add-widget-test/SKILL.md`, `flutter-build-responsive-layout/SKILL.md`, `ui-ux-pro-max/SKILL.md` and its pro-rules, `dart-run-static-analysis/SKILL.md`, `better-writing/SKILL.md`, `verification-before-completion/SKILL.md`; repository `.agents/skills/vital-mobile-copy/SKILL.md`. Existing pinned package APIs and the approved stack supersede generic skill examples.
