# Reminder alert controls (D12a)

Adds optional reminder sound and vibration choices on top of the existing
Android reminder channel. The choices default to the original behaviour and are
persisted in the encrypted settings, then applied to a real notification
channel. The operating system remains authoritative.

## Skills read

- `/home/mike/.codex/skills/flutter-expert/SKILL.md`
- `/home/mike/.codex/skills/codebase-memory/SKILL.md`
- `/home/mike/.codex/skills/flutter-apply-architecture-best-practices/SKILL.md`
- `/home/mike/.codex/skills/dart-add-unit-test/SKILL.md`
- `/home/mike/.codex/skills/flutter-add-widget-test/SKILL.md`
- `/home/mike/.codex/skills/flutter-build-responsive-layout/SKILL.md`
- `/home/mike/.codex/skills/ui-ux-pro-max/SKILL.md`
- `/home/mike/.codex/skills/dart-run-static-analysis/SKILL.md`
- `/home/mike/.codex/skills/better-writing/SKILL.md`
- `/home/mike/.codex/skills/verification-before-completion/SKILL.md`
- `/home/mike/.codex/skills/kotlin-specialist/SKILL.md`
- `/home/mike/.codex/skills/mobile-android-design/SKILL.md`
- `/home/mike/Development/true_grit_vital/.agents/skills/vital-mobile-copy/SKILL.md`

The repository copy skill is absent from this worktree, so the root checkout's
tracked copy was read directly. No skill loader was required.

## Primary platform guidance

Android notification-channel documentation, checked 22 October 2026:
<https://developer.android.com/develop/ui/views/notifications/channels>.
After creation a channel's sound, vibration and importance cannot be changed by
the app, and the user controls them in system settings. The app therefore never
edits or deletes an existing channel. A different app choice uses an explicit
new channel id; the system settings link already used by the reminders surface
remains the repair path.

## Behaviour

- `reminder_alerts` in the encrypted settings stores `{"sound": bool,
  "vibration": bool}`. An absent record means the legacy default: sound and
  vibration on. A malformed record is an explicit read failure, not a silent
  reset.
- The saved choice is durable intent. Persistence and native application are
  reported separately: an unapplied native change stays saved and offers
  `Retry`; a failed settings write restores the previous choice. A failed
  channel creation is a native apply failure, not a claimed effect.
- The adapter's "already applied" cache is cleared whenever the captured
  record store or adapter instance changes. A restore, a native journal reset
  or a replacement adapter therefore re-applies even an identical choice.
- A missing channel is reported as unknown, not enabled. Capability
  observation, scheduling and the screen therefore never treat a lost channel
  as a working one; the existing repair and `Retry` paths create it again.
- A changed choice is applied to the native reminder journal, then capability
  observation is refreshed. Existing reminder tokens, snooze packets, action
  envelopes, dataset epoch and reconciliation guards are untouched.
- The Android legacy channel id and configuration remain exactly
  `vital_reminders_v1`, created with only `IMPORTANCE_DEFAULT` and no explicit
  vibration call, which is the original OS behaviour. Other combinations use
  explicit variants (`_s1v0`, `_s0v1`, `_s0v0`) with short user-visible names.
  Choosing the legacy combination again returns to the original channel and its
  OS state.
- Both ordinary and event-end notifications use the stored choice. API 26 and
  later report `alertChoicesAvailable`; earlier hosts hide the controls rather
  than exposing a placebo switch.
- Choices are disabled while the app or active channel is blocked, so a new
  channel cannot quietly bypass a system mute. The existing permission,
  channel and exact-alarm diagnostics remain the repair path.
- No new permission, dependency, SDK change, schema change, DND/critical
  override or delivery guarantee. There is no follow-up timing; D12 remains
  partial.

## Copy review

`Alert options` is a two-word authored heading. `Sound` and `Vibration` describe
the on state, with short positive helper text. The vibration helper says it is
used only when Android allows it, so the screen does not promise vibration. The
legacy channel keeps its original creation without an explicit vibration call.
`Retry` and `Settings` are one-word actions. The shared `SettingsToggleRow`
keeps one semantic control, right-aligned switches, keyboard activation and a
target above 48 px. The section states that Android can override the choices
and that delivery is not guaranteed.

## Captures

- [light](light-reminder-alerts.png)
- [dark](dark-reminder-alerts.png)
- [dark, 320 px and 2x text](dark-reminder-alerts-narrow-double-text.png)

Generated with:

```
./tool/flutterw test test/screen_reminder_alerts_capture_test.dart \
  --dart-define=VITAL_SCREEN_REMINDER_ALERTS_CAPTURE=docs/design/reviews/2026-10-22-next-five/alerts
```

## Verification

- `./tool/flutterw analyze`: `No issues found!`
- `./tool/flutterw test test/reminders test/data/reminder_store_test.dart test/platform/reminders_test.dart test/screen_reminder_alerts_capture_test.dart`:
  123 tests passed, including the existing reminder lifecycle, snooze, action,
  capability-race, host-recovery and UI suites.
- `python3 android/app/src/test/run_reminder_tests.py`: 35 engine tests passed,
  including alert default/identity/serialization/configuration,
  missing-or-muted-channel and no-cancel/no-reschedule checks.
- A temporary compile of `Reminders.kt`, `ReminderJournal.kt`,
  `ReminderEngine.kt` and `ReminderAlerts.kt` against the installed Android 36
  `android.jar` with local Flutter/MainActivity/R stubs exited 0. The stubs are
  disposable and not committed.
- Focused Dart coverage includes durable reload after a cold start and dataset
  replacement, identical-choice reapplication after a store or adapter change,
  write/apply failure and retry, channel failure after saving, lock blocking
  and unlock retry, channel-blocked UI, MethodChannel serialization,
  light/dark, 320 px/2x text and reduced motion.

## Graph evidence

Parent-supplied project `home-mike-Development-true_grit_vital`, Tier 2. A
fresh `check_index_coverage` for the inspected reminder/store/native paths
returned `no_recorded_issue` with `metadata_match` and the best-effort caveat;
it is not proof of completeness. Private Dart edges were read from exact
source, including `reminder_store.dart` and `record_store.dart`.

## Remaining limits

Lead integration review added the OS-mute check at the native selection boundary,
as well as the visible settings controls. A startup/restore apply or stale UI
capability read cannot switch away from a blocked active channel. Missing
channels can still be repaired; selecting an already active choice does not
invent a new effect. The native suite now passes 37 engine checks, including
rejection before journal mutation and preservation of scheduled reminders.
Android channel creation/override rules were checked against the official page
above during lead review. Host integration verification is recorded in the
batch review after all five packages are merged.

Physical-device notification sound, vibration, channel creation, system mute,
lock-screen presentation and TalkBack were not exercised; no emulator or APK
build was run. Delivery remains platform-controlled. Variant channels remain
visible in Android settings after a choice changes, by design, because deleting
a channel would discard the user's own channel settings. D12 follow-up timing
is not part of this slice.
