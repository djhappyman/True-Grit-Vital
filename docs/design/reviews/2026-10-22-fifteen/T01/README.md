# T01 snapshot isolation

Implemented on the assignment checkout based on parent `cdefb2a` plus assignment
commit `bc14ce6`. This hardens snapshot inspection/rekey only. It does not close
the original ticket 23/24 release gates or implement automatic backups.

## Finding

The supplied source log is
`/home/mike/Development/true_grit_vital/.scratch/vital-implementation/third-five-2026-10-22/verification/native-boot.log`.
Its warnings at lines 8 and 26 both originate at `inspectBackupSnapshot`, called
by creation's initial inspection and decrypted self-verification respectively.

The pinned Drift 2.35.2 source at
`/home/mike/.pub-cache/hosted/pub.dev/drift-2.35.2/lib/src/runtime/api/db_base.dart`
uses an isolate-local `Map<Type, int>` named `_openedDbCount` and increments it
using `runtimeType`. It does not compare executor identities or file paths.
`RecordStore.open` creates a fresh `NativeDatabase.createInBackground(file, ...)`
each time. The snapshot uses the separate encrypted file created by `VACUUM INTO`.
These warnings are therefore class-registration false positives for this path,
not evidence that inspection is sharing the live executor.

`baseline.log` reproduces that warning with the new regression before the fix:
the test fails its empty-warning assertion. No production diagnostic flag is
set by the implementation.

## Change

- Each inspection or rekey operation runs in a short-lived `Isolate.run` worker.
  Only explicit path/key copies, ports and inventory values cross the boundary.
  The closure is constructed in a separate function so it cannot capture the
  parent's observer, token, open database or other unsendable state.
- Each worker owns its freshly created Drift executor. Rekey closes the old-key
  connection before opening/closing the verification connection. Completion and
  failures follow awaited closure. Cancellation is cooperative; the worker is
  never killed while its executor owns the snapshot.
- The existing synchronous validation observer remains in the calling isolate.
  A batch acknowledgement preserves its cancellation/exception boundary, and
  observer exceptions are rethrown with their original identity and stack after
  the worker has closed. Normal production inspection does not request batches.
- Live stores retain Drift's registration and duplicate warning. A regression
  explicitly opens a duplicate live connection and checks that it still warns.

Production changes are limited to `lib/data/backup_store.dart` and the isolate
import in `lib/data/record_store.dart`. `lib/backup/backup_service.dart` needs no
change. There is no schema, archive, KDF, dependency, policy, UI or copy change.

## Verification

Saved command logs have trailing whitespace removed only.

All commands use Flutter 3.47.7 / Dart 3.13.5 through `./tool/flutterw`.
Formatting uses that SDK's `dart format` on changed files only.

- `./tool/flutterw test --no-pub test/backup/backup_snapshot_isolation_test.dart --reporter expanded`
  passes all 6 tests in `isolation.log`, with no printed Drift warnings.
  On Linux, `/proc/self/fd` proves the live and snapshot database files are both
  open at the observer boundary and have different paths. After success, wrong
  key, invalid stored quantity, thrown observer and cancellation, the snapshot
  database and its sidecars have no open descriptors. Concurrent writes survive
  inspection cancellation, rekey and cancelled backup creation; generation is
  unchanged, the captured inventory stays fixed, and a previous archive is
  byte-for-byte unchanged and still validates. Concurrent snapshot inspections
  also complete independently.
- `./tool/flutterw test --no-pub test/backup/backup_snapshot_isolation_test.dart test/backup/backup_inspection_cancellation_test.dart test/backup/backup_service_test.dart test/data/backup_store_test.dart --reporter expanded`
  passes 25 tests in `regressions.log`. The existing wrong-key test at
  `test/data/backup_store_test.dart:207` deliberately calls ordinary
  `RecordStore.open` while its live store remains open, so it still prints a
  duplicate-class warning. The stack does not originate in snapshot inspection.
- `./tool/flutterw test --no-pub test/backup/backup_snapshot_isolation_test.dart test/restore/restore_preparation_test.dart test/restore/restore_preparation_cancellation_test.dart test/restore/restore_flow_test.dart --reporter expanded`
  passes 17 tests in `restore-regressions.log`. These existing restore tests
  still print duplicate-class warnings from ordinary store opens in
  `prepareRestoredDatabase`, test fixture opens and `RestoreActivation._generation`.
  Those paths are outside T01's owned snapshot inspection/rekey scope; their
  diagnostics remain enabled and no change is made to hide them.
- `./tool/flutterw analyze --no-pub lib/data/record_store.dart lib/data/backup_store.dart lib/backup/backup_service.dart test/backup/backup_snapshot_isolation_test.dart`
  reports no issues in `analyze.log`.
- `git diff --check` passes.

No UI captures apply to this data-layer change. Native combined boot/build,
physical-device verification, power-loss and broader release gates remain with
the lead. Descriptor checks are Linux-only; the remaining behaviour checks run
without `/proc` on other hosts. Added isolate startup overhead has not been
profiled on a physical phone.

## Sources and graph limits

Read the parent AGENTS, implementation README, original tickets 23/24,
specification README/implementation plan/content contract and engineering skills
policy directly; ignored files were taken from the parent checkout. Original
tickets, gates, discovery and shared design documents are unchanged.

Used the live parent graph `home-mike-Development-true_grit_vital`, generation
`2026-10-22T22:17:00Z`: project/status, exact symbol search, both-direction trace
and snippet for `inspectBackupSnapshot`, plus coverage checks on evidence paths.
The snippet covers only the signature, so the implementation and lifecycle were
read directly. Coverage reports no recorded issue for existing evidence paths;
this is best-effort metadata, not completeness proof. The new test is absent
from the parent graph and was read directly. The parent was not reindexed into
this worktree.

API checks used installed pinned sources and current primary documentation:
[Drift FAQ](https://drift.simonbinder.eu/faq/),
[Drift isolates](https://drift.simonbinder.eu/isolates/),
[Dart Isolate.run](https://api.dart.dev/dart-isolate/Isolate/run.html) and
[Dart Isolate.spawn](https://api.dart.dev/dart-isolate/Isolate/spawn.html).
The current online Dart pages identify 3.13.6; the actual `Isolate.run` contract
was also read from the installed 3.13.5 SDK's `lib/isolate/isolate.dart`.

## Exact skill files read

All were accessible before dependent implementation. No native loader was
required. Widget guidance was read as required by the ticket; no widget is
changed, so additional UI/copy/layout/Riverpod/router guidance does not apply.

- `/home/mike/.codex/skills/flutter-expert/SKILL.md`
- `/home/mike/.codex/skills/flutter-expert/references/project-structure.md`
- `/home/mike/.codex/skills/flutter-expert/references/performance.md`
- `/home/mike/.codex/skills/codebase-memory/SKILL.md`
- `/home/mike/.codex/skills/verification-before-completion/SKILL.md`
- `/home/mike/.codex/skills/dart-add-unit-test/SKILL.md`
- `/home/mike/.codex/skills/dart-run-static-analysis/SKILL.md`
- `/home/mike/.codex/skills/debugging-wizard/SKILL.md`
- `/home/mike/.codex/skills/flutter-apply-architecture-best-practices/SKILL.md`
- `/home/mike/.codex/skills/flutter-add-widget-test/SKILL.md`
