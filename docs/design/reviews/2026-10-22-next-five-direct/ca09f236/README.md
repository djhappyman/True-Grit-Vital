# Settings backup status

Task branch: `t3/settings-backup-status` at baseline `0dab613`.

`SettingsBackupStatus` adds a compact, read-only receipt summary to Settings
Data. It selects the latest `savedAt` across current-generation receipts rather
than trusting list order or `verifiedAt`. A verified-only receipt shows the
plain empty state. Loading, load error with Retry, lock hiding and the existing
Backup route command are covered. It never starts a backup or asks for a
password, and the saved time uses the shared display time-format and device-zone
formatter.

The duplicate Backup settings navigation row was replaced by this card so the
Data section keeps one Backup command.

Verification:

- `./tool/flutterw test --no-pub test/settings/backup_status_test.dart`: 8 tests passed.
- `./tool/flutterw test --no-pub test/settings/settings_ui_test.dart test/settings_vault_ui_test.dart`: 13 tests passed.
- `./tool/flutterw analyze`: no issues found.
- `git diff --check`: clean.

The focused tests cover unsorted saved receipts, verified-only receipts, load
failure and Retry, live refresh after a confirmed save, old-generation
filtering, lock hiding, Backup navigation and Back return, and 320 px with
double text in both themes.

Skill files read: `flutter-expert`, `codebase-memory`, `dart-add-unit-test`,
`dart-run-static-analysis`, `verification-before-completion`,
`flutter-add-widget-test`, `flutter-build-responsive-layout`,
`interaction-design`, `ui-ux-pro-max`, `better-writing` and the repository
`vital-mobile-copy` skill. The last skill and the ignored specification docs
were read directly from the main checkout because this worktree does not contain
gitignored `.agents/`, `AGENTS.md` or `docs/specification/` files. No skill-file
read failure occurred.

Graph: Tier 2 `codebase-memory-mcp` project
`home-mike-Development-true_grit_vital`. `check_index_coverage` reported no
recorded issue for the cited existing source paths. The new widget and test are
absent from the pre-change index, so they were read and verified directly.

Remaining limits: physical-device screen-reader, external-file retention and
measured performance remain outside this host test run. No roadmap or shared
specification document was edited.
