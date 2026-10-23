# R01 structured food and bedtime plan requirements

Status: implemented locally for lead reconciliation. Physical-device gates remain open.

## Capability

Each immutable daily plan version can carry optional food and bedtime labels chosen
explicitly in the schedule editor. `ScheduleRequirement` stores one optional food label
(`Before food`, `With food`, `After food`, `Empty stomach`) and an optional `At bedtime`
label. The default is no structured requirement at all.

These labels are literal authored choices, not inferred meal times, dose intervals,
clinical validation or evidence of compliance. The editor adds no timing rule, window or
follow-up reminder around them. The existing authored `instructions` text remains a
separate field and is never parsed, rewritten or replaced.

## Persistence and copies

The requirement is additive JSON inside the existing encrypted version snapshot:

```json
"requirements": {"food": "withFood", "bedtime": true}
```

The key is omitted when no choice exists. Missing, empty, `food: null` and
`bedtime: false` decode as unspecified. Unknown food names and wrong value types are
rejected instead of silently dropping a newer label. Empty structured values cannot enter
a saved version. No SQL schema change was made.

All existing version-copy paths carry the requirement: ordinary saves, daily edits,
pause/restart close-and-propose paths, resolver-internal timing copies, phase origin
copies, pause editor and phase editor. Earlier audit versions keep their exact labels, so
a later edit cannot rewrite a saved action's historical context.

Drafts persist `requirementFood` and `requirementBedtime` beside the existing instruction
field through the ordinary draft allowlist. The encrypted restart and backup snapshot
retain the labels.

## Interface

The canonical schedule editor now has a `Requirements` section under `Plan instructions`
with two labelled chip groups:

- `Food`: `Not set`, `Before food`, `With food`, `After food`, `Empty stomach`.
- `Bedtime`: `Not set`, `At bedtime`.

The helper states that the labels are saved with this plan version and add no timing rule.
Chips are the existing 48 px `ScheduleChoiceChip` with explicit selection semantics. The
obsolete unavailable-preview copy was removed.

Saved labels appear as compact badges in the schedule preview, Today plan rows, substance
overview and the shared substance summary. Authored instruction text remains displayed
separately.

## Reports and exports

`SavedPlanInstruction` may now carry the exact original-version requirements. A version
with labels but no text is still linked to its saved action, so reports and JSON exports
can name the labels. Report text adds `Before food`/`With food`/`After food`/
`Empty stomach` and `At bedtime` only under the existing `includeNotes` consent. Without
consent the instruction object stays absent and no label enters output.

CSV columns were not changed; requirement labels are not appended to the CSV instruction
text column. Export semantics now describe the optional `requirements` object and its
notes-consent boundary.

## Files

- `lib/domain/scheduling/schedule_requirement.dart` (new)
- `lib/domain/scheduling/daily_plan.dart`
- `lib/domain/scheduling/saved_plan_instruction.dart`
- `lib/data/daily_codec.dart`
- `lib/data/daily_store.dart`
- `lib/data/pause_store.dart`
- `lib/data/plan_instruction_output_store.dart`
- `lib/domain/scheduling/daily_resolver.dart`
- `lib/domain/scheduling/phase_plan.dart`
- `lib/domain/drafts/ordinary_draft.dart`
- `lib/domain/reports/report_model.dart`
- `lib/domain/exports/export_document.dart`
- `lib/features/plans/plan_form.dart`
- `lib/features/plans/plan_requirement_badges.dart` (new)
- `lib/features/plans/pause_editor.dart`
- `lib/features/plans/phase_editor.dart`
- `lib/features/plans/today_plan_rows.dart`
- `lib/features/substances/substance_overview.dart`
- `lib/features/substances/substance_summary.dart`
- `lib/l10n/app_en.arb` and regenerated localisations
- `test/data/plan_requirements_test.dart` (new)
- `test/plan_requirements_ui_test.dart` (new)
- `test/screen_schedule_capture_test.dart`
- `test/screen_schedule_support.dart`
- `test/screen_schedule_layout_test.dart`
- `test/design_substance_summary_fixture.dart`

No dependency, SDK, timing-policy or follow-up-reminder change was made.

## Copy review

- Section heading: `Requirements`, meta `Optional`.
- Helper: `Choose any labels that apply. They are saved with this plan version and add no
  timing rule.`
- Group headings: `Food`, `Bedtime`.
- Choices: `Not set`, `Before food`, `With food`, `After food`, `Empty stomach`,
  `At bedtime`.
- Sentence case and existing command words (`Preview`, `Save`, `Discard`) are unchanged.

## Verification

Commands were run from this worktree with `./tool/flutterw`.

- `analyze`: `No issues found!`
- `test/data/plan_requirements_test.dart`: 11 passed. Covers legacy JSON shape, omitted and
  empty values, exact round-trip, unknown/malformed rejection, empty-version rejection,
  value equality, encrypted restart, backup restore, immutable audit versions, pause/phase
  copies, notes-consented reports/exports, consent exclusion and frozen saved-action
  labels after an edit.
- `test/plan_requirements_ui_test.dart`: 5 passed. Covers saved/selected chips, draft
  persistence and restore, clear-and-save, preview badges, overview and shared summary,
  and 320 px at double text in light and dark with reduced motion.
- Related regression run: 59 passed across `plan_instructions_test`,
  `plan_instruction_output_test`, `plan_instructions_ui_test`,
  `screen_schedule_layout_test`, `design_substance_summary_test` and
  `design_substance_overview_test`.
- Store regression run: 68 passed across `daily_store_test`, `pause_store_test` and
  `phase_store_test`.
- `test/screen_schedule_capture_test.dart` with
  `--dart-define=VITAL_SCHEDULE_CAPTURES=<this directory>`: 2 passed, producing the
  real-font narrow light and dark captures below.

No physical Android device was attached. Reminder delivery and native behaviour were not
validated here.

## Captures

- `light-schedule-full.png` and `dark-schedule-full.png` show the complete 320 px editor at
  real font weights, including the selected `With food` and `At bedtime` labels.
- `light-schedule.png` and `dark-schedule.png` show the narrow viewport composition.

## Limitations / lead reconciliation

- The lead owns `PlanTimingPolicy? timingPolicy`; this work deliberately keeps the separate
  property and codec key `requirements`. Same-file conflicts in `DailyPlanVersion`,
  `daily_codec.dart` and `plan_form.dart` should be reconciled by the lead after this
  commit.
- CSV export keeps its existing columns. Requirements are available in consented JSON
  export and report text, not as a new CSV column.
- Physical-device reminder and restore gates are unchanged and remain open.

Lead integration also displays the original version's labels in recorded/skipped
History cards and interval preview. Bounded existing page queries join the
immutable plan audit, validate identity and retain the expectation privacy
boundary. The historical labels are checked after an edit and encrypted restart.
Timing policy and requirements coexist through the editor, codec, copies and
draft allowlist. Combined checks are recorded in the batch-level review.
