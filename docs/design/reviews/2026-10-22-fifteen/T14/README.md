# T14 pending reminder cancellations

Recovered from checkpoint worktree `/home/mike/.t3/worktrees/true_grit_vital/t3-7745e46e`
after its event stream was lost. That worktree was inspected read-only, its
task-owned modified/untracked files were copied into this freshly bound
worktree, and every acceptance point was reviewed and finished here. No other
worker's files were touched.

Base: parent `cdefb2a` plus assignment commit `bc14ce6`; this checkout also
contains the integrated T01 snapshot isolation and T15 audit commits, which are
unrelated to this task.

## Finding

`ReminderHealthPanel` rendered both cancellation facts through one generic
line, `reminderIncomplete` (`Some alerts are not prepared in this scope. Reopen
Vital and retry.`). The last bounded pass already reports the two counts
separately, plus when it checked the device, but the panel did not say how many
were awaiting an operating-system confirmation, how many receipts failed to
confirm a stop, or what that uncertainty means. A pending cancellation is not a
failed dose record and not a confirmed stop, so one catch-all incomplete line
was not honest enough.

## Change

- New `lib/features/reminders/reminder_cancellations.dart` projects the existing
  `ReminderHealthSummary` into the only cancellation claim the panel may show.
  It adds no timer, retry policy, engine call or scheduling policy.
- `lib/features/reminders/reminder_health_panel.dart` now shows one compact
  factual line while attention exists. `Details` expands the separate
  awaiting-confirmation and not-confirmed counts, the last check (or `unknown`
  when no coverage time was reported), the "counts can overlap" clarification
  when both are above zero, and a plain explanation for each state. The
  explanation says an alert may still appear or sound; it never claims a stop
  or delivery.
- The count block is hidden while the app is locked. The summary itself clears
  when the reminder controller rebuilds for a replaced dataset, so retained
  counts are not carried over.
- Counts appear only after a pass that attempted work and did not fail, and only
  when a count is above zero. Zero shows nothing rather than a success claim;
  an untouched surface, a failed pass and an unavailable summary publish no
  cancellation claim.
- No repair control was added. `RemindersPage` already renders the existing
  `Retry` action immediately below this panel, and the pending help says Vital
  checks again when the app is reopened. No follow-up timing, sound or
  notification-default policy changed.
- `lib/app/reminder_health.dart` needed no change; the existing summary already
  carries the factual fields.
- ARB entries are prefixed `batch15T14`; generated localisations were
  regenerated with `./tool/flutterw gen-l10n`.

## Copy review

Skills read before writing strings: repository `vital-mobile-copy`,
`better-writing`, `interaction-design`, `ui-ux-pro-max` (index and workflow),
`accessibility-compliance`, `flutter-expert` plus its widget and Riverpod
references, `dart-add-unit-test`, `dart-run-static-analysis`,
`flutter-add-widget-test`, `codebase-memory` and
`verification-before-completion`.

- Authored heading is one word (`Details`); no new command button was added.
- Full localisable messages, named placeholders and plural metadata for both
  count lines. No fragments around values and no em/en dashes.
- Plain UK English. `Android` wording matches the existing reminder-health and
  limits copy in this app. Nothing claims that an alert was delivered, stopped
  or confirmed cancelled.
- `These counts can overlap.` is shown only when both are non-zero, because one
  obsolete alert can still need a stop and also lack a confirming receipt. The
  two numbers are never summed.
- Live region is limited to the compact state line so an unchanged panel does
  not repeatedly announce the disclosure body.

## Verification

All commands used the pinned Flutter 3.47.7 / Dart 3.13.5 through
`./tool/flutterw`; formatting used that SDK's `dart format` on the changed files
only. The lead preserved final logs locally under
`.scratch/vital-implementation/fifteen-2026-10-22/verification/T14-lead-*.log`.

- Lead verification: 46 tests passed across `reminder_cancellations_test.dart`,
  `reminder_health_panel_test.dart`, `reminder_health_test.dart` and
  `reminder_ui_test.dart` under `test/reminders/`.
- Scoped `./tool/flutterw analyze --no-pub` on the four changed/added Dart
  files reports no issues.
- A final capture-only rerun passed both theme cases after hiding the fixture's
  debug banner. The six refreshed captures use the real widget, theme and
  localisations, with synthetic data. Both themes were inspected by the lead.
- `git diff --check` passes.

Covered invariants:

- pending-only, unconfirmed-only and mixed counts select the correct compact
  sentence and details;
- zero, an unreported summary, a failed pass and a locked app publish no
  cancellation claim, and unlock restores it;
- a later pass replaces the earlier count and a zero pass removes the block;
- the two counts stay separate, with the overlap note only when both exist;
- unknown check time stays unknown rather than borrowing the current clock;
- keyboard Space/Enter expands and collapses the disclosure;
- both themes at 2x text render at 320, 390 and 430 logical pixels without a
  layout exception.

## Captures

`light-*` and `dark-*` at 390 logical pixels show the compact and expanded
panel. `*-narrow.png` shows the expanded panel at 320 logical pixels and 2x
text. These are synthetic fixtures: two pending and one unconfirmed
cancellation, a completed coverage pass at 09:00 Europe/London.

The pre-existing `No prepared coverage for Reminders` line is still visible
above the cancellation block in these captures. Any outstanding cancellation
keeps the repair report's convergence `deferred`, which makes each scope
`partial`, so the existing scope copy deliberately withholds a prepared-through
claim and points at `Retry`. T14 did not change that rule; it is recorded here so
the lead can decide whether the broader scope wording needs a separate ticket.

## Limits

- No physical Android device, TalkBack run, native cancellation receipt or
  combined build/boot was performed in this worker; the lead owns those.
- `checkedAt` is the latest coverage check time carried by the summary. It is a
  factual check time, not proof of an OS cancellation result.
- Widget tests can prove rendering, labels, focus and disclosure state, not the
  operating system's actual cancellation behaviour.
