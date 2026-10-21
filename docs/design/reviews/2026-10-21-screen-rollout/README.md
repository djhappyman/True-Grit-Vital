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

## Events

- [Light](light-events.png), [dark](dark-events.png), [full light](light-events-full.png) and [full dark](dark-events-full.png) show saved cycles and prescription courses. [Detail light](light-event-detail-full.png), [detail dark](dark-event-detail-full.png) and [narrow/double text](dark-events-narrow-double-text.png) use the same real components and routes.
- Create, status filters, selection/combined history, details, Configure, end review and revisions remain live. Counts are whole-collection only when the first page is complete; larger collections say shown and preserve paging. Notes remain an explicit preview.
- Lead review separated unresolved dates from Active, corrected end-only labels and date-progress arithmetic, refreshed list timing every minute and reused the shared badge/button styling. Event titles get their full card width. Progress describes elapsed dates, not dose adherence.
- Lead verification: 33 regression checks, 12 final UI checks, five framework/safe-area checks, two loaded capture checks and clean analysis. Includes partial/end-only dates, midnight status rollover, real forms, paging and 320 px double text. Device accessibility/performance gates remain open.

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

## Settings

- [Light](light-settings.png), [dark](dark-settings.png), [full light](light-settings-full.png), [full dark](dark-settings-full.png), [narrow light](light-settings-narrow.png) and [narrow dark](dark-settings-narrow.png) show the single hub with group choices above its overview card.
- All/General/Privacy/Data filters retain real capability-gated destinations. Existing appearance, profile, reminders, diagnostics, help, licences, reports, exports, backup, restore and privacy forms remain canonical. Automatic backups and FHIR are non-interactive previews; storage totals are explicitly unavailable.
- Lead integration replaced the inherited custom gesture/focus rows with shared shadcn controls and shared surface geometry. Keyboard and accessible activation remain one command per row. Preview badges stack at narrow widths/large text.
- Lead verification: 74 regression checks, eight hub/capture checks, five framework/safe-area checks and clean analysis. Includes 320/390/430 px double text, route capability guards, keyboard activation, lock/draft and appearance recovery. Physical-device screen-reader/performance gates remain open.

## Substance overview

- [Light](light-substance-overview.png), [dark](dark-substance-overview.png), [full light](light-substance-overview-full.png) and [full dark](dark-substance-overview-full.png) use the saved earlier substance-detail composition on the existing `/substance/:id` route.
- Identity, Record/Combine/Stock, factual low-stock notices and Overview/Schedule/Stock/History jumps share one page and scroll owner. Saved plan Edit/Add, exact balances, bounded recent records, linked events, product/source context, files and recorded-use periods stay connected.
- Full identities, quantities, unknown zone, pause, incomplete next-dose calculation and More hints remain visible. No fabricated Active, clinical notes, capacity, runout or on-time values are shown. The secondary page keeps Back navigation.
- Lead verification: 49 overview/collection/summary regression checks, 18 final overview checks including real section jumps, five framework/capture checks and clean analysis. Includes lock, mounted plan refresh, per-plan edit identity, low-balance routing and narrow/double-text layouts. Physical-device accessibility/performance gates remain open.

## Panel detail

- [Light](light-panel-detail.png), [dark](dark-panel-detail.png), [full light](light-panel-detail-full.png), [full dark](dark-panel-detail-full.png) and [320 px / double-text](light-panel-detail-narrow-2x-full.png) captures show saved results and a synthetic original-file attachment.
- Exact values, units, source ranges and applicability, source flags, dates, revisions, linked record names, Edit/Void/Restore, Files and Trends use the existing durable records. Observations retain their measured-date label. Range filters and paging remain valid after a correction changes the result count.
- Copy uses saved attachment hashes and the real clipboard. The page explicitly distinguishes these from whole-record verification, describes its 25-file window and opens the existing supporting-content export selection. FHIR, categories and accession metadata remain gaps.
- Lead verification: 60 supporting/panel regression checks, two loaded capture checks, five framework checks and clean analysis. Includes source-range semantics, read-only revisions, shortened result paging and export scope. Native screen-reader and physical-device performance checks remain open.

## Route sweep

The [route captures](routes/) contain 34 existing routes in both themes. The sweep checks device safe areas, fixed navigation and opaque/reduced-effects layouts using synthetic records. Secondary editors keep their existing forms and shared framework. Missing-record and unavailable-platform states are intentional; the loaded screen captures above provide evidence for their populated counterparts.

## Final verification

- `./tool/flutterw test --reporter expanded`: **1,855 passed**, one existing opt-in skip, no failures.
- `./tool/flutterw analyze`: no issues. Final changed-test formatting and `git diff --check` passed.
- All 34 visual-framework routes passed in both themes. Loaded screen-specific captures and narrow/double-text checks are recorded above.
- The real Secret Service Linux boot test passed encrypted persistence, navigation, structured export, PDF reporting and backup creation. Its temporary namespace and key were removed successfully.
- Normal Linux debug build and Android debug APK build passed. The Android SDK XML-version warning did not prevent the APK build. Android release signing remains deliberately unconfigured; use `./tool/flutterw run --debug` for development installation.
- Physical-device screen-reader testing, native notification delivery, production signing and measured glass/performance gates remain open. Host checks do not close them.

Run logs are local under `output/stitch-screen-rollout-2026-10-21/`. The [roadmap](../../roadmap.md) tracks the remaining screens and capability gaps.
