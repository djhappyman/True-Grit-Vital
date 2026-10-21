# Screen rollout review

Native Flutter captures from the remaining-screen rollout. Designs use the saved [Stitch batch](../../stitch/2026-10-20/README.md), with the owner’s later [History reference](../../references/2026-10-21-history-calendar/README.md) replacing that screen’s composition. These screenshots use the real shared components and synthetic local records.

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

## Inventory

- [Light](light-stock.png), [dark](dark-stock.png), [full light](light-stock-full.png) and [full dark](dark-stock-full.png) show the canonical Stock page with synthetic known, low and unknown balances.
- [Narrow light](light-stock-narrow.png) and [dark](dark-stock-narrow.png), plus [bottom light](light-stock-narrow-bottom.png) and [dark](dark-stock-narrow-bottom.png), show deliberate stacking and reachable actions at 320 px / double text.
- Notice cards use a bounded page from the collection-wide notice query, prioritised within that page, with further notices explicitly indicated. Container paging stays separate. Exact balances, Adjust, notice settings and item-scoped Add remain real; the unscoped Add section opens Substances to choose an item. Scanning, lots, expiry, capacity and forecasts remain named gaps.
- A container without an active notice says No notice. Zero stock with notices disabled is never described as stocked. The redundant profile label is removed, and surfaces use shared semantic geometry.
- Lead verification: 39 stock regression checks, five visual/safe-area checks, an expanded 320/390/430 px double-text check and clean project analysis. Physical-device accessibility, keyboard and performance evidence remains open.

## History

- [Light](light-history.png), [dark](dark-history.png), [full light](light-history-full.png) and [full dark](dark-history-full.png) implement the owner’s replacement monthly-calendar composition, using the same shared surfaces, controls, palette and type scale.
- Opens on today with a month grid, exact saved-record markers and compact selected-day cards. Whole cards open the existing source/correction flow. Full names, quantities and units stay visible. Calendar dots represent recorded/skipped/voided entries, not adherence or planned rest days.
- Filters, range/timeline browsing, charts, structured exports and other reports stay behind the calendar’s filter control. The audit preview, weekly strip and repeated metadata are removed from the default view. The monthly PDF action opens the existing report review with the displayed month’s exact dates, including year boundaries.
- Existing source return, moved anchors, bounded paging, stale refresh, combined records, lock guards and four-destination fixed dock remain in place. Calendar counts refresh after source inspection and stay unavailable on failed reads.
- Lead verification: nine focused calendar/UI checks, 43 History/combined regression checks, five visual/safe-area checks and clean analysis. Narrow and double-text cases retain all days and actions; the month heading stacks above controls at large text sizes. Physical-device screen-reader and performance evidence remains open.

## Labs

- [Light](light-screen-labs.png), [dark](dark-screen-labs.png), [full light](light-screen-labs-full.png) and [full dark](dark-screen-labs-full.png) show the canonical supporting-records collection with synthetic panels and observations.
- Latest values use a live window of up to 75 dated records and 60 markers. Original values, units, dates, source ranges and flags remain visible; comparisons require matching units, laboratory, method and specimen. No clinical classifications or invented charts are added.
- Kind/date/unknown/voided filters and record paging remain connected. The latest summary states its separate date scope when date filters are selected. Add, detail, trends, linked records, files and reports use the existing routes. This secondary screen retains Back navigation.
- Lead review kept linked names beside one-word Open actions, included source flags in accessible summaries and prevented a failed latest read from being hidden by an empty-state message.
- Lead verification: 64 regression checks, seven final UI checks, five framework/safe-area checks, two loaded capture checks and clean project analysis. Width checks include 320 px at double text and 430 px. Physical-device screen-reader and performance evidence remains open.

Run logs are local under `output/stitch-screen-rollout-2026-10-21/`. The [roadmap](../../roadmap.md) tracks the remaining screens and capability gaps.
