# Next feature batch

D08 and D10 use OpenCode’s `opencode/deepseek-v4.1-flash-free` in isolated worktrees. The lead owns D20 and integration review. D08 and D20 are host verified; D10 remains under review and repair.

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

## D10: Review repairs

The initial implementation is merged locally for combined verification: optional notes/tags under More, revision/draft persistence, optional secondary skip reasons, action/source history and privacy-gated dose notes in reports/exports. It is **not accepted as complete**. The same free DeepSeek model owns a new bounded repair round for skip reasons in structured exports and reports, full encrypted metadata restore coverage, legacy empty-context command replay and old correction-draft recovery. There was no lead agreement to omit skip reasons from outputs. No new release is part of this batch.

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
