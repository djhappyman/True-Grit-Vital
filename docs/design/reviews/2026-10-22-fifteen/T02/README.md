# T02 attachment authority

T02 implements attachment action guards for tickets 16/04 and D23. The lead explicitly extended ownership to `renameAttachment` in `lib/data/attachment_store.dart` for its optional guarded-writer callback. No schema, dependency, backup, report or shared design-document changes were made. This is host evidence, not release acceptance.

## Reproduced defects

- Holding native handoff publication open, then locking and unlocking, renaming the file, or revising its owner caused the original controller to initiate one stale share in each case. The initial three regression tests each reported expected `0`, actual `1` against the original controller, then passed with the guards.
- An uncertain delete followed by a route change from file A to file B reused the retained command for A. Confirming B actually deleted A. The real SQLite/widget reproduction failed because A was unexpectedly null; [before](verification/viewer-identity-before.log) and [after](verification/viewer-identity-after.log) preserve this evidence.
- Confirmation methods initially accepted replies based only on `mounted`; double activation could open overlapping decisions. Queued rename had no optional authority check at its transaction boundary.

## Changes

- Capture the exact store/generation, file owner/revision/content version and live target revision. Recheck delayed results before opening or initiating a save/share. The live target revision is separate from the file's historical target revision; historical files remain readable after a dose is voided.
- Reuse the controller's provider lifecycle and add an action epoch invalidated by lock. A lock/unlock cycle cannot renew an old initiation. Route-location epochs also reject departure followed by return; opening a decision dialog leaves the location unchanged.
- Serialise Open and confirmation entry. Reset retained viewer action identity when its route ID changes, and prevent a retained rename draft from saving through another file's route. Keep entered text, command identity, durable draft recovery and focus return.
- Keep delete's existing committed-operation lookup before any retry. Dispatch against its captured store and use the existing delete transaction hook to reject expired authority before commit. An expired completion cannot redirect another route.
- Add backwards-compatible `canCommit` to rename. Check before queuing, after transaction acquisition and after writes, before durable commit. Expiry rolls back both the revision and operation audit; retry can use the same uncommitted command ID.
- Cancel only the unoffered handoff owned by that initiation. Release its pin against the originating store and wipe save buffers. An already initiated, offered handoff keeps its valid lifetime and factual outcome through lock. If its provider has already closed the originating store, the existing session-recovery or handoff-expiry path reclaims the abandoned pin.
- Keep the existing serialized preview decoder, source epoch and pin cleanup unchanged. Added delayed-decode tests verify disposal on lock/unlock and route departure, alongside the existing source/dataset replacement cases.

All app wording uses existing localised messages. Errors after an expired lock cycle use the existing retry message rather than asking an already unlocked person to unlock. No ARB entries or generated locale changes were needed. Existing short headings and one-word commands are retained.

## Verification

The final command logs are under `verification/`; terminal trailing whitespace is removed without changing diagnostic text. They cover real encrypted temporary SQLite metadata and command audits, with fakes only at the native picker/handoff/decoder boundaries. No external sends or user files were used.

- `final-ui.log`: 13 passing UI/regression cases, including three existing regressions for raw rename input/focus, uncertain delete command identity and already initiated share lifetime.
- `final-service.log`: 12 passing action/history cases. This selection includes the delayed delete route test also present in the UI selection; counts are not distinct totals.
- `preview.log`: the earlier final focused run passed 23 cases, including all five preview lifecycle tests. Subsequent changes did not alter the production preview implementation.
- `captures.log`: six passing cases produce 12 real Flutter captures, light/dark at 320, 390 and 430 logical pixels, 2x text, reduced motion, and simulated top/bottom safe areas. Viewer and cancellable Share confirmation are captured for each case. These are synthetic fixtures.
- `analyze.log`: whole-project `./tool/flutterw analyze --no-pub`.
- Formatting uses the Dart 3.13.5 formatter bundled with Flutter 3.47.7, scoped to the six changed Dart files. `git diff --check` checks patch whitespace.

After normal pinned dependency setup (`./tool/flutterw pub get --offline` when the cache is available), reproduce the dedicated behaviour checks:

```sh
./tool/flutterw test --no-pub test/attachment_action_ui_test.dart test/attachments/attachment_action_authority_test.dart test/attachment_preview_lifecycle_test.dart
./tool/flutterw analyze --no-pub
./tool/flutterw test --no-pub test/attachment_action_ui_test.dart --plain-name 'T02 capture' --dart-define=VITAL_UI_SNAPSHOTS=docs/design/reviews/2026-10-22-fifteen/T02
```

The deliberate independent-dataset fixtures emit Drift's debug warning about multiple database instances. They use separate database files and executors; the warning has not been globally suppressed.

Physical Android/iOS handoff, screen-reader behaviour and device performance remain with the original gates and lead integration. No native app build or boot was run by this worker.

## Source and API checks

The parent graph project was `home-mike-Development-true_grit_vital`, initially ready at `2026-10-22T22:17:00Z`; later coverage checks observed its live refresh. This was a bounded attachment audit: search pagination was exhausted, relevant class and handoff traces were read in both directions, and coverage was checked for source evidence paths. Class traces largely expose `createState`, not async method internals; they do not establish absence of dependencies. Exact worktree source reads supplied the authority for the changed paths. The parent index was not repointed to this worktree.

Pinned source checked: Flutter's `packages/flutter/lib/src/widgets/routes.dart` (`ModalRoute.of` rebuilds when current-route status changes), go_router 18.1.0 `lib/src/router.dart` (route information listener and navigation APIs), and flutter_riverpod 3.4.3 `lib/src/core/consumer.dart` (provider listeners). Current primary references were [Flutter route status](https://api.flutter.dev/flutter/widgets/ModalRoute/isCurrentOf.html) and [Riverpod refs](https://riverpod.dev/docs/concepts2/refs). Generic skill examples did not authorise a package or state-management upgrade.

Required parent assignment/specification documents, both original tickets, the interaction blueprint/rollout row, components and roadmap were read directly. Original gates and discovery documents were preserved.

## Exact skill files read

All files were accessible; no native loader was needed.

- `/home/mike/.codex/skills/flutter-expert/SKILL.md`
- `/home/mike/.codex/skills/flutter-expert/references/widget-patterns.md`
- `/home/mike/.codex/skills/flutter-expert/references/riverpod-state.md`
- `/home/mike/.codex/skills/flutter-expert/references/gorouter-navigation.md`
- `/home/mike/.codex/skills/flutter-expert/references/performance.md`
- `/home/mike/.codex/skills/flutter-expert/references/project-structure.md`
- `/home/mike/.codex/skills/codebase-memory/SKILL.md`
- `/home/mike/.codex/skills/verification-before-completion/SKILL.md`
- `/home/mike/.codex/skills/dart-add-unit-test/SKILL.md`
- `/home/mike/.codex/skills/dart-run-static-analysis/SKILL.md`
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
- `/home/mike/.codex/skills/ui-ux-pro-max/references/quick-reference.md` (sections 1–3 for the final interaction/accessibility pass)

Task cleanup removes this worker’s generated build/test caches and disposable `/tmp` files after verification. The committed logs, before/after defect evidence and intended captures remain.
