# Design implementation roadmap

Owner direction, 21 October 2026: implement the audited design and feature gaps with GLM Flash agents, five at a time, beginning with Today, Substances and a unified substance overview. This roadmap supplements the original 28-ticket implementation plan; it does not declare its device/release gates complete.

Baseline: `90581ec`. The audit examined all 13 current PNG/HTML pairs in [the saved reference archive](stitch/2026-10-20/README.md), the earlier substance-detail variant, current source and 66 synthetic light/dark captures. The 43 framework/design checks passed. Colours, white light canvas, fixed dock and safe-area framework exist; screen composition and capability parity remain incomplete.

## First batch

All five packages start from the same baseline and [contract](implementation-contract.md). Status changes to integrated only after lead review, functional tests and light/dark visual inspection. A worker result is not acceptance. Physical accessibility and device performance remain open.

| ID | Package | Acceptance | Status |
| --- | --- | --- | --- |
| D01 | Today dashboard and compact schedule | Real next-dose timing, truthful daily completion, compact time groups and PRN entry points; retain source/strength checks, taken/skip/snooze/extra/edit/Undo and incomplete calculation warnings. | Integrated; host verified |
| D02 | Substance search and filters | Search the whole local collection, not only loaded cards; type filters, clear/reset, bounded paging and preserved browsing state. Compact cards open the substance overview. | Integrated; host verified |
| D03 | Substance summaries | Reusable live schedule, labelled strength, stock and next-dose summary from existing records; explicit partial/unknown states and compatible units; no guessed doses or dates. Mount in the list and share per-container presentation with the overview, avoiding duplicate schedule/stock sections. | Integrated; host verified |
| D04 | Substance overview | One reachable overview with identity, recording, schedule, stock, recent history and existing context links. Preserve existing detail/history URLs and all editing routes. Missing/deleted/locked records recover truthfully. | Integrated; host verified |
| D05 | Shared summary components | Reusable compact row, factual metric and progress components using current tokens/shadcn; safe growth for long names and large text, keyboard/semantics, light/dark and reduced effects. Adopt in D01/D03/D04 during integration. | Adopted in Today, list and overview; host verified |

## Batch verification

D01–D05 were integrated and reviewed on 21 October 2026. The full Flutter suite
passed **1,750 tests**, with one existing opt-in skip; project analysis was clean.
The real Secret Service Linux boot test passed encrypted persistence, navigation
and export, followed by a successful normal Linux debug build. The 28 Today
checks cover timing boundaries, partial totals, future doses and compact actions.

[Light/dark Flutter screenshots](reviews/2026-10-21/README.md) are committed for
Today, Substances and the overview. The full-suite visual harness also checked
all 34 listed routes in both themes, fixed navigation and device safe areas.
Physical-device accessibility, native delivery and measured glass/performance
gates remain open. Review also fixed the widget fixture's database-close deadlock
and an older report-attachment lease that incorrectly expired from the report's
captured timestamp instead of the live file-operation clock.

## Remaining audit gaps

These are recorded follow-up work, not completed features. Dependencies refer to this roadmap. Detailed behaviour is resolved before its implementation slice. The owner subsequently requested explicit visual placeholders for missing dashboard capabilities; those previews do not complete the feature backlog and never write invented data.

| ID | Feature gap | Required outcome / dependency | State |
| --- | --- | --- | --- |
| D06 | Weekly overview and quick-record favourites | Real date selection/weekly summaries, configurable PRN shortcuts and collapsible recorded section with accessible Undo. Define completion denominator and incomplete data; follows D01. | Backlog |
| D07 | Substance status and counts | Whole-collection active/paused/PRN filters and counts with explicit unscheduled/mixed-plan cases. Item type and PRN schedule remain distinct; follows D02/D03. | Backlog |
| D08 | Integrated substance setup | Identity, schedule and optional opening stock in a coherent flow with drafts/recovery; optional authored instructions and notes; follows D04. | Backlog |
| D09 | Dose presets and recording sheet | Exact preset quantities and strength equivalents, visible stock consequence, compact responsive sheet/page, existing validation and durable actions retained. | Backlog |
| D10 | Dose context and skip reasons | Persist optional notes, food/context tags and skip reason through edits, history, exports and backup/restore. Optional observation entry links use existing supporting-record semantics. | Backlog |
| D11 | Schedule requirements and tolerance | Optional food/bedtime instructions and explicit timing-tolerance rules, reflected consistently in forms, summaries and history. No treatment recommendations or inferred maximum doses. | Backlog: behaviour definition |
| D12 | Reminder follow-ups and alert controls | Explicit opt-in follow-up timing, cancellation/reconciliation after actions, sound/haptic choices and truthful OS limitations. Existing snooze is preserved. Native/device evidence required. | Backlog |
| D13 | Stock lots and expiry | Optional lot/batch and expiry metadata, pack capacity and restock flow; schema migrations, history and export/backup round trips. | Backlog |
| D14 | Stock forecast and inventory overview | Low/adequate/paused filtering, remaining-capacity display and schedule-based run-out estimates. PRN, unknown balance, incompatible units and incomplete schedules stay explicit; follows D03/D13. | Backlog |
| D15 | Refill delivery and scanning | Native refill notices extend the currently agreed in-app stock notices. Barcode/pack recognition needs exact source, licence, privacy and ambiguity rules; manual entry always works. | Backlog: bounded design/source review |
| D16 | Event overview | Status filters/counts, progress cards and linked-substance/recorded/skipped summaries using existing event dates/membership. Surface supported notes and configure/history actions. | Backlog |
| D17 | Lab dashboard | Latest-value cards, categories, comparable trends/sparklines, baseline changes and source-range indicators with original units/flags. Existing panels/attachments/trends remain available. | Backlog |
| D18 | Lab panel detail | Categorised results, comparable prior values, context links and protected original-file/hash actions. Add accession/source identifiers only with storage and export support. | Backlog |
| D19 | History presentation and timing | Compact day groups, filters/counts, weekly summaries and on-time/late indicators using D11 rules; planned slots and actual use remain distinct. Existing reports/CSV/PDF remain available. | Backlog |
| D20 | Settings and vault overview | Reference-informed sections/tabs, real storage/record counts and report date shortcuts. Preserve current manual backup/restore, lock, appearance, privacy and support. | Backlog |
| D21 | Automatic protected backups | Define destination, retention, encryption/key availability and interrupted-exit recovery. Never claim a completed backup before durable verification. | Backlog: lifecycle design |
| D22 | FHIR/HL7 export | Select exact format/version/mapping and validate representative artifacts; preserve units, source meaning and privacy. Existing structured exports are not FHIR/HL7. | Backlog: format decision |
| D23 | Remaining screen and light-theme parity | Review forms, labs, events, history and settings against references; establish white-canvas light layouts where no current light PNG exists. Keep full names, amounts and safe areas. | Backlog, after feature slices |
| D24 | Selected glass surfaces | Validate targeted chrome on representative hardware, preserve opaque/reduced-effects fallback. Current glass validation gate remains off until measured evidence permits it. | Device gate open |

## Claims requiring decisions

- Clinical optimal/risk/target classifications and causal response claims are generated examples, not agreed clinical functionality. Show original lab source ranges/flags and factual comparisons; any additional interpretation needs an explicit product decision and evidence.
- SHA-256 attachment verification does not establish a complete tamper-evident ledger, zero gaps or clinical validity. A ledger-integrity feature needs its own threat model and implementation.
- Critical/DND override and exact notification delivery depend on platform permissions and policy. Do not promise delivery guarantees.
- The app records actual use even when stock is insufficient, a plan is paused or an event has ended. Design examples must not introduce clinical dose advice or block truthful recording.

## Review evidence

Every integrated package records loaded skill paths, changed capabilities, tests, reference comparisons and remaining limits here. Lead integration runs static analysis, relevant regression tests, shared UI checks and a native boot check. Full release acceptance retains the original G01–G08 gates.

Current batch evidence: search/type filters, live summaries, shared rows/metrics and the linked substance overview are integrated. Lead review repaired hidden filters, stale type names, pending counts, silent truncation and timezone uncertainty. The 46 combined overview/collection/summary tests passed; a subsequent 19-test overview/framework run covers the final copy and light/dark captures. Rendered light/dark list and overview screens were inspected. The first batch subsequently passed 1,750 tests with one skip, static analysis and a native Linux boot check (commit `5c47400`). Physical device gates remain open. Delegation identities and outcomes are retained locally under `.scratch/vital-implementation/design-parity-2026-10-21/`.

## Closer Stitch layouts

The owner requested a direct rebuild of Dashboard and Substances against the saved Stitch batch, implemented by the lead without delegation. The export's original font weights, text sizes, pill geometry, grouped timeline, week strip, search and collection cards replace the looser first-batch composition. Existing logging, Undo, snooze eligibility, search/type filters, paging, stock, overview, settings and profile routes remain connected.

D06 remains backlog for real weekly browsing and configurable favourites; the week strip and Configure action explain their unavailable states. The recorded section now expands to the existing history controls. The blood-pressure sparkline is labelled Design preview and opens supporting records. The refill card shows an existing stock notice when available and opens real stock management; a days-of-stock forecast remains D14. Status filters (D07), remaining screens (D23) and measured glass (D24) remain open.

See the [native light/dark screen review](reviews/2026-10-21-stitch-rebuild/README.md). Host checks do not close physical-device gates.

## Remaining screen rollout

The owner approved the closer Dashboard/Substances layout (`466d638`) and authorised each DeepSeek Flash reviewer to move into implementation. All ten remaining screen purposes were reviewed against their saved PNG and HTML; implementations use one canonical screen per purpose, not separate light/dark or mock-only variants. Workers use isolated worktrees; the lead owns the shared foundation and verifies each integration. Local review/task evidence is under `.scratch/vital-implementation/screen-plan-2026-10-21/`.

| ID | Screen and canonical route | Live wiring / missing design sections | State |
| --- | --- | --- | --- |
| S00 | Shared components | One typography/palette/geometry source and surface/control renderer behind existing Vital and Stitch APIs. Existing fields, notices, badges, icons and page shells remain reusable. Preserve the approved Dashboard/Substances compositions. | Integrated; 63 focused checks and analysis passed |
| S01 | Create, `/create` | Real catalogue/custom identity, type/unit/product choices and durable Save. Schedule/stock require the saved item identity: use existing editors, with truthful save-first states; no nested draft controllers or invented atomic setup. | Integrated; 59 focused checks and analysis passed |
| S02 | Record, `/record/:id` and correction mode | Restyle the existing DoseForm with sheet geometry. Preserve actual time/DST, exact amount/unit, stock/strength/source/product/site controls, recovery and return/Undo. Presets/context/vitals remain labelled previews where unsupported. | Integrated; 70 regression checks, 5 visual/safe-area checks and analysis passed |
| S03 | Schedule, `/schedule/:id` | Keep all six real modes, calendar/interval/block sections, pause/phase links, reminders and Preview then Save. Missing requirement/tolerance/follow-up rules are previews. | Integrated; 44 regression checks, 7 visual/safe-area checks and analysis passed |
| S04 | Stock, `/stock/me` | Real container balances, notices, source labels, Adjust/restock/waste/measure and Add. Forecast/capacity/lot/expiry/scanning stay explicit gaps under D13–D15. Never use an ambiguous bare +/- stock mutation. | Integrated; 39 regression checks, 5 visual/safe-area checks and analysis passed |
| S05 | Events, `/events` | Real event creation/detail/configuration/revisions, memberships, dates and end review. Show factual date progress, not adherence; unresolved dates get their own review state. Counts/filters explicitly describe the loaded page when incomplete. Notes and whole-event recorded/skipped counts need storage/query support. | Integrated; 33 regression checks, 12 final UI checks, 5 framework checks, loaded captures and analysis passed |
| S06 | History, `/history` | Owner’s 21 October replacement: month calendar, compact selected-day cards, disclosed filters/tools and monthly PDF report selection. Existing cursor/anchor/source/correction/exports stay connected. Inline Undo remains on `/recorded`. | Integrated; calendar revision verified with focused UI, regression, light/dark and safe-area checks |
| S07 | Labs, `/supporting` | Restyle existing supporting records, panels, observations and trends; keep Add/detail/files/source/reports live. Latest values use a live bounded window of 75 dated records and 60 markers, with exact comparable previous values. Original dates, units, ranges and flags stay visible; no invented risk/optimal/causal labels. | Integrated; 64 regression checks, 7 final UI checks, 5 framework checks, loaded light/dark captures and analysis passed |
| S08 | Panel detail, `/supporting/me/:id` | Original values/units/source ranges/flags, dates, revisions, Edit/Void/Restore, attachments, trends and source versions. Resolve linked record names. Stored file hashes are not proof of a verified complete ledger; FHIR remains D22. | Implementing |
| S09 | Settings, `/settings` | One hub using real capability-gated Profile/Appearance/Privacy/Reminders/Reports/Exports/Backup/Restore/Help routes. Preserve their existing forms and controls. No cloned appearance/wipe/backup workflows or fabricated counts/auto-backup claims. Shared shadcn rows keep keyboard and accessible activation. | Integrated; 74 regression checks, 8 hub/capture checks, 5 framework checks and analysis passed |
| S10 | Substance overview, `/substance/:id` | Reshape the existing unified overview: Record/Combine, per-plan Edit, stock, recent use, history and context links. Missing identity editing/refill/notes/forecast controls are truthful previews, not new duplicate detail pages. Section jumps share one scroll owner. | Integrated; 49 regression checks, 18 final overview checks, 5 framework/capture checks and analysis passed |

History now follows the owner’s [replacement calendar reference](references/2026-10-21-history-calendar/README.md). Other rows use the corresponding current export in the [snapshot index](stitch/2026-10-20/README.md); S10 also uses the saved earlier substance-detail reference where no current overview export exists. Mislabelled generated headers are corrected to the real destination. Other existing utility/editor routes inherit the foundation and receive the route-capture sweep; they do not get alternative mock implementations or a fifth dock destination.

Acceptance for every screen: loaded light/dark captures; white light canvas and green-black/mint dark surfaces; 320/390/430 px plus 2× text; fixed existing dock and device/keyboard safe areas; no accidental action/quantity wrapping, clipped names or overflow (deliberate stacking/scrolling for narrow/large text); 48 px targets; real actions retain draft, lock, stale/revision, exact-unit, stock and Undo guards. Add no dependencies and do not enable unmeasured glass. Extend shared components instead of copying local colours, text scales, borders or button skins. Existing D06–D24 capability gaps stay open until their actual behaviour is implemented.
