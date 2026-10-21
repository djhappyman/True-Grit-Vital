# Screen rollout review

Native Flutter captures from the remaining-screen rollout. Designs come only from the saved [Stitch batch](../../stitch/2026-10-20/README.md). These screenshots use the real shared components and synthetic local records.

## Create

- [Light](light-create.png), [dark](dark-create.png), [full light](light-create-full.png) and [full dark](dark-create-full.png): loaded canonical `/create` form at 390 × 844, including device safe areas.
- Catalogue/custom entry, personal types, form/unit/product choices, encrypted drafts and guarded Save remain connected. Schedule and stock use the existing editors after identity is saved. Notes and food-context rules remain capability gaps.
- Lead integration: 59 focused interaction/design checks passed; whole-project analysis was clean. Focused tests cover 320 px / 2× text, full custom type names and a simulated open keyboard. Capture checks are recorded separately in the run evidence.
- Physical-device screen-reader and measured-performance checks remain open.

## Schedule

- [Light](light-schedule.png), [dark](dark-schedule.png), [full light](light-schedule-full.png) and [full dark](dark-schedule-full.png) captures use the canonical saved-plan editor with two synthetic planned times.
- All six modes, calendar/interval/block controls, pause and phase links, saved-plan reminders and Preview then Save remain live. Requirements, tolerance and follow-up alerts are labelled previews.
- The screen changes page composition through the shared durable-form hook. Draft, lock, generation and post-save recovery guards stay in the base form. Pause/Resume uses the actual pause interval.
- Lead verification: 44 regression checks, seven visual/safe-area checks, a final two-capture run after typography adjustment, and clean whole-project analysis. Layout checks include 320 px / 2× text with a keyboard, 390/430 px targets and landscape insets. Existing lock checks now locate Create fields by their visible labels.
- These host checks do not close native reminder-delivery, screen-reader or performance gates.

## Record dose

- [Light](light-record.png), [dark](dark-record.png), [full light](light-record-full.png) and [full dark](dark-record-full.png) captures show the existing `/record/:id` form composed as a sheet. Correction uses that same form.
- Real quantity/unit, source/strength, product, site and actual-time controls remain connected. The stock consequence uses exact quantities and labelled conversion; unknown, limit and deficit states stay explicit. Context tags and dose-attached vitals remain previews. Observations opens the existing supporting records.
- The outer compatibility panel is disabled for this composition. Shared form guards stay central. The heading says Record dose, and the displayed time respects the existing 12/24-hour preference while entry stays HH:MM.
- Lead verification: 70 regression checks, five visual/safe-area checks and clean project analysis. Coverage includes 320/390/430 px at normal/double text, actual save/correct/Undo, source replacement, lock recovery and reminder navigation. The capture harness waits for the form/source reads and can save a full composition as well as the device viewport.
- Physical-device keyboard, screen-reader and performance evidence remains open.

Run logs are local under `output/stitch-screen-rollout-2026-10-21/`. The [roadmap](../../roadmap.md) tracks the remaining screens and capability gaps.
