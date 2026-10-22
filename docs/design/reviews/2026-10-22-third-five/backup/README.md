# Backup receipt inspection

D21c, 22 October 2026. The lead extended the existing Backup history disclosure;
no backup destination, retention or automatic-backup policy was introduced.

- All, Saved and Unconfirmed choices filter the retained current-dataset
  receipts. The count describes only those retained matches, not external files.
- Creation, archive checking and confirmed saving remain separate facts. An
  unconfirmed receipt does not assert that a file was never saved.
- Settings and Backup now share the same latest-confirmed-save selector. It
  compares save times rather than receipt insertion/check order. Filtering the
  history never changes this summary or starts a backup operation.
- Pending refresh/error states hide retained receipt details; Retry is explicit.
  Existing dataset generation fences, twenty-receipt bound and lock guards remain.

## Verification

Focused commands and final results are recorded in the parent batch review.
`test/backup_receipt_filters_test.dart` covers unordered save/check facts,
filters and live changes, keyboard activation, idle backup state, refresh/error/
retry, both themes, safe areas, 320/390/430 px and double text/reduced motion.
Existing backup history, Settings, store and creation-flow tests cover lock,
dataset fencing, bounded encrypted receipts, cancellation and safe save states.

The screenshots are real Flutter synthetic fixtures. Dates follow the device
zone, as the visible receipt help states; they are not medical records. Reviewed
Saved and narrow Unconfirmed/filter views use shared Vital surfaces, segments,
buttons and disclosure motion. Long facts scroll vertically without reducing
text size. Physical-device screen-reader/performance checks remain open.

## Sources read

- `/home/mike/.codex/skills/flutter-expert/SKILL.md` and
  `references/widget-patterns.md`.
- Installed `codebase-memory`, `better-writing`, `dart-add-unit-test`,
  `flutter-add-widget-test`, `flutter-build-responsive-layout`,
  `dart-run-static-analysis`, `interaction-design`, `ui-ux-pro-max` and
  `verification-before-completion` skill files.
- Repository `.agents/skills/vital-mobile-copy/SKILL.md`, current specification,
  engineering policy, content contract, shared components and interaction
  blueprint/Backup and Settings rollout rows.

Tier2 graph exploration and exact-path coverage found no recorded issue for
production evidence files. Test paths were discovered with graph and checked;
nonexistent guessed paths were discarded. Full relevant source was read where
the graph snippets ended at a signature. Clean coverage is best-effort evidence,
not a proof of parser completeness.

Final host checks: four new receipt-filter tests passed, followed by 24 existing
backup-history/Settings/store/creation-flow regressions. Whole-project analysis
reported no issues. New tests were rerun after the 430 px and narrow filter
capture additions and all four passed. Screenshots were inspected in light and
dark, including the 320 px double-text filter/content views.
