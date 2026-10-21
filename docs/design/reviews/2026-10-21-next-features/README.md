# Next feature batch

D08 and D10 run on OpenCode’s `opencode/deepseek-v4.1-flash-free` in isolated worktrees. The lead owns D20. Assignment does not imply agent completion.

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
