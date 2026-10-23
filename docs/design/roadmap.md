# Design implementation roadmap

## Roadmap completion, 23 October

The owner authorised five concurrent lanes and lead takeover of rate-limited
work, from `3787c65`. Owner confirmed user-set timing/follow-ups off until configured, manual backups
for now, FHIR R4 JSON with preview/Save and confirmed scan suggestions.

| Lane | Work | Model | State |
| --- | --- | --- | --- |
| R01 | Structured food/bedtime schedule requirements | Free DeepSeek | Integrated; host verified |
| R02 | Reproducible physical-performance/glass validation tooling | Free GLM → lead | Tooling integrated; real host run verified; device acceptance open |
| R03 | FHIR R4 reviewed export | Paid OpenCode DeepSeek → lead | Integrated; host verified; official R4 sample validation has no errors |
| R04 | Local pack scanning and confirmed associations | Direct API DeepSeek → lead | Integrated; exact open-source dependencies admitted; device camera check open |
| R05 | Timing labels, follow-up reminders and integration | Lead | Integrated; host verified; physical delivery open |

The lead completed GLM's unfinished checkpoint and recovered the usage-limited
and insufficient-balance DeepSeek lanes. [Batch evidence](reviews/2026-10-23-roadmap-finish/README.md)
records review, real decoder checks, the integrated Android debug build, native
Linux boot and the limitations of each package.

Original device/release/catalogue admission gates remain separate. No Android
device is currently attached; host checks cannot close physical validation.
Briefs and task identities are retained under
`.scratch/vital-implementation/roadmap-finish-2026-10-23/`.

## Medicine catalogue

Viability review, 23 October: use an official versioned bulk dataset, search it
locally, and offer common-name shortcuts plus custom entry. The existing
catalogue/update foundation is available but currently contains synthetic
fixtures; no production corpus is admitted by this review.

For the UK, [NHSBSA dm+d](https://www.nhsbsa.nhs.uk/pharmacies-gp-practices-and-appliance-contractors/nhs-dictionary-medicines-and-devices-dmd)
is the preferred candidate: weekly refreshes and product/pack identifiers.
[TRUD terms](https://isd.digital.nhs.uk/trud/user/guest/group/0/pack/1/subpack/24/licences)
require an account and licence acceptance; exact chosen fields and third-party
rights must pass G05 before import/distribution. Do not equate the separate
SNOMED Drug Extension corpus with the dm+d XML licence.
[RxTerms](https://lhncbc.nlm.nih.gov/MOR/RxTerms/) offers monthly bulk files/API
and friendly names but is US-focused; it is a later regional candidate, subject
to its own exact-data admission. A manually curated starter is possible but
needs ongoing source-backed maintenance, not guessed doses or strengths.

Prefer downloading public catalogue releases over live medicine-name API
searches. Show last-updated/source/version facts and keep the old verified
release until a replacement validates. Suggested disclosure: “Internet is
needed to update the medicine list. Your health records and searches are not
sent.” This is proposed copy for that future flow, not a newly shipped updater.
Connections necessarily reveal network metadata such as IP addresses, and
explicit exports can leave the device; a literal “no information ever leaves”
promise would be inaccurate. Updates improve freshness without guaranteeing
that every medicine is current or available. This review approves no network
endpoint, dataset, licensing account or automatic update behaviour.

## Fifteen-task continuation, 22 October

Owner authorised three Sol 6.1 workers, two OpenCode-hosted DeepSeek workers
and ten direct-API DeepSeek workers concurrently, based on `cdefb2a`.
Fourteen implementation/hardening packages and one original-plan acceptance
audit are integrated below. Host verification does not close release gates.

| Task | Scope | Lane | State |
| --- | --- | --- | --- |
| T01 | Isolate protected backup snapshot database lifetimes | Sol 6.1 | Host verified |
| T02 | Guard protected file actions across lifecycle changes | Sol 6.1 | Host verified |
| T03 | Unify safe report date and seed validation | Sol 6.1 | Host verified |
| T04 | Make catalogue search cancellable and calm | OpenCode DeepSeek → lead | Host verified |
| T05 | Edit saved exact dose presets | OpenCode DeepSeek → lead | Host verified |
| T06 | Add reviewable export date shortcuts | Direct DeepSeek → lead | Host verified |
| T07 | Preserve exact lab trend source context | Direct DeepSeek → lead | Host verified |
| T08 | Filter stock movements before paging | Direct DeepSeek → lead | Host verified |
| T09 | Explain changes in stock metadata history | Direct DeepSeek → lead | Host verified |
| T10 | Inspect recorded injection-site history | Direct DeepSeek → lead | Host verified |
| T11 | Show exact seven-day plan preview totals | Direct DeepSeek → lead | Host verified |
| T12 | Reject invalid quick-entry dates and preserve task context | Direct DeepSeek → lead | Host verified |
| T13 | Fence destructive privacy confirmation to its dataset | Direct DeepSeek → lead | Host verified |
| T14 | Explain pending reminder cancellations | Direct DeepSeek → lead | Host verified |
| T15 | Reconcile the roadmap and original 28-step acceptance plan | Direct DeepSeek → lead | Host verified |

The lead recovered interrupted OpenCode checkpoints, finished the remaining
implementation, reviewed changes and ran combined host verification. See the
[finished batch and remaining work](reviews/2026-10-22-fifteen/README.md). Briefs,
ownership, acceptance criteria and task identities are retained under
`.scratch/vital-implementation/fifteen-2026-10-22/`. Timing tolerance,
reminder follow-up policy, scanning/FHIR choices, automatic-backup lifecycle
and physical-device/distribution gates retain their existing status.

## Third five-task continuation, 22 October

Owner authorised another five tasks under the same concurrent direct-DeepSeek
conditions, based on `55f84cf`. These extend existing capabilities; unresolved
timing, scanning, automatic-backup and release decisions remain open.

| Slice | Outcome | Owner | State |
| --- | --- | --- | --- |
| D13g | Explicit Name/Expiry inventory sorting before paging | DeepSeek | Host verified |
| D13h | Inspect the saved dose behind a stock movement | DeepSeek | Host verified |
| D20b | Review a report scoped to one substance from its overview | DeepSeek | Host verified |
| D16d | Open canonical event History with saved membership/boundary semantics | DeepSeek | Host verified |
| D21c | Inspect saved/check-only backup receipts with consistent latest-save facts | Lead | Host verified |

Acceptance briefs and task identities are retained under
`.scratch/vital-implementation/third-five-2026-10-22/`. All five slices are host verified after lead review, focused checks and
theme/layout inspection. Final combined verification passed 108 tests, clean
analysis and a real Secret Service Linux build/boot/persistence/navigation/export
check. [Batch evidence](reviews/2026-10-22-third-five/README.md). Device gates remain open.

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
| D06 | Weekly overview and quick-record favourites | Real date selection/weekly summaries, configurable PRN shortcuts and collapsible recorded section with accessible Undo. Define completion denominator and incomplete data; follows D01. | Host integrated and verified: real weekly/day browsing, persisted favourites |
| D07 | Substance status and counts | Whole-collection active/paused/PRN filters and counts with explicit unscheduled/mixed-plan cases. Item type and PRN schedule remain distinct; follows D02/D03. | Host integrated and verified: whole-collection status queries and counts |
| D08 | Integrated substance setup | Identity, schedule and optional opening stock in a coherent flow with drafts/recovery; optional authored instructions and notes; follows D04. | Host integrated and verified: resumable optional setup, canonical editors, authored instructions/private notes and privacy-gated outputs |
| D09 | Dose presets and recording sheet | Exact preset quantities and strength equivalents, visible stock consequence, compact responsive sheet/page, existing validation and durable actions retained. | Integrated on host: exact user-saved/latest-schedule presets, responsive sheet and stock/strength previews; durable guards retained |
| D10 | Dose context and skip reasons | Persist optional notes, food/context tags and skip reason through edits, history, exports and backup/restore. Optional observation entry links use existing supporting-record semantics. | Host integrated and verified: optional dose context and skip reasons, revision/draft recovery, private outputs and encrypted restore |
| D11 | Schedule requirements and tolerance | Optional food/bedtime instructions and explicit timing-tolerance rules, reflected consistently in forms, summaries and history. No treatment recommendations or inferred maximum doses. | Host integrated: optional structured food/bedtime labels and user-set timing windows, off until configured; immutable history, drafts, previews and consented outputs verified |
| D12 | Reminder follow-ups and alert controls | Explicit opt-in follow-up timing, cancellation/reconciliation after actions, sound/haptic choices and truthful OS limitations. Existing snooze is preserved. Native/device evidence required. | Host integrated: sound/vibration controls plus one optional user-set follow-up, off by default, with cancellation/terminal receipt guards; physical-device delivery remains open |
| D13 | Stock lots and expiry | Optional lot/batch and expiry metadata, pack capacity and restock flow; schema migrations, history and export/backup round trips. | Host integrated and verified: schema 24, lot/expiry/exact capacity, guarded edits and paged history, structured provenance, encrypted restore and optional capture-time stock details in reports |
| D14 | Stock forecast and inventory overview | Low/adequate/paused filtering, remaining-capacity display and schedule-based run-out estimates. PRN, unknown balance, incompatible units and incomplete schedules stay explicit; follows D03/D13. | Host integrated and verified: store-backed search/counts/filters, exact capacity proportions and conditional forecast from tomorrow; incomplete inventory reads and unsupported schedules are explicit |
| D15 | Refill delivery and scanning | Native refill notices extend the currently agreed in-app stock notices. Barcode/pack recognition needs exact source, licence, privacy and ambiguity rules; manual entry always works. | Host integrated: opt-in Android low-stock/refill notices and local ZXing scanning with manual fallback and explicit Link/Use; atomic bounded encrypted associations, no invented national pack mapping; physical camera and notification delivery checks remain open |
| D16 | Event overview | Status filters/counts, progress cards and linked-substance/recorded/skipped summaries using existing event dates/membership. Surface supported notes and configure/history actions. | Host integrated: saved private notes, whole-event summaries, whole-collection status counts and filter-before-page browsing; captured status instants and filtered-page clamping preserve current context |
| D17 | Lab dashboard | Latest-value cards, categories, comparable trends/sparklines, baseline changes and source-range indicators with original units/flags. Existing panels/attachments/trends remain available. | Host integrated: latest dated values across the filtered collection with 24-marker pages and exact counts; trends sample 24 points and comparisons 48 results with disclosed limits; duplicate prior results retain uncertainty |
| D18 | Lab panel detail | Categorised results, comparable prior values, context links and protected original-file/hash actions. Add accession/source identifiers only with storage and export support. | Host integrated: complete current-record prior comparisons relative to the viewed panel, exact source/date matching and order-independent ambiguity; saved accession/report identifiers remain available through outputs and encrypted restore |
| D19 | History presentation and timing | Compact day groups, filters/counts, weekly summaries and on-time/late indicators using D11 rules; planned slots and actual use remain distinct. Existing reports/CSV/PDF remain available. | Host integrated: monthly calendar, compact day cards, filters/counts, activity summaries and factual timing labels from the captured user-set window; unknown/date-only/voided entries stay unlabelled |
| D20 | Settings and vault overview | Reference-informed sections/tabs, real storage/record counts and report date shortcuts. Preserve current manual backup/restore, lock, appearance, privacy and support. | Host integrated and verified: live whole-collection counts, measured database storage and reviewed report date shortcuts; device gates remain open |
| D21 | Automatic protected backups | Define destination, retention, encryption/key availability and interrupted-exit recovery. Never claim a completed backup before durable verification. | Deferred by owner on 23 October: keep manual encrypted backups for now. Verified manual archive checks and confirmed-save receipts remain available; automatic destinations and scheduling are not implemented |
| D22 | FHIR/HL7 export | Select exact format/version/mapping and validate representative artifacts; preserve units, source meaning and privacy. Existing structured exports are not FHIR/HL7. | Host integrated: FHIR R4 4.0.1 collection Bundle with exact recorded values, truthful mapping review and explicit Save; official representative validation has zero errors and 11 disclosed warnings, with terminology lookup disabled; national-profile/EHR acceptance remains separate |
| D23 | Remaining screen and light-theme parity | Review forms, labs, events, history and settings against references; establish white-canvas light layouts where no current light PNG exists. Keep full names, amounts and safe areas. | Integrated on host: all ten canonical screens, white light theme and shared framework; physical-device gates remain open |
| D24 | Selected glass surfaces | Validate targeted chrome on representative hardware, preserve opaque/reduced-effects fallback. Glass is enabled by the owner’s 23 October family-design direction; physical validation remains a separate open gate. | Measurement fixture, validator and optional-budget comparator integrated; all four workloads exercised on host; Workout-family glass enabled by owner direction; physical measurements and adopted budgets open |

## Current five-task batch

Owner authorised another five tasks on 22 October 2026. The free DeepSeek worker
owns selected-week history summaries (D19a); three paid workers use OpenCode's
direct DeepSeek API model, `deepseek/deepseek-flash` (DeepSeek V4.1 Flash 1017),
for saved schedule instructions (D11a), reminder sound/vibration controls (D12a)
and optional stock-source facts in reports (D13b). The lead owns protected-backup
verification history (D21a) and takes over any rate-limited work. Three workers
run alongside the lead; the fourth starts when a slot opens.

These are scoped slices. Timing-tolerance rules, automatic backups and
physical-device delivery checks remain open. Each package received focused
functional checks, shared-component UI review and lead integration before its
host status changed. Task briefs and delegation identities
are retained locally under `.scratch/vital-implementation/next-five-2026-10-22/`.

D21a is implemented and host verified by the lead: bounded encrypted receipts,
separate checked/saved facts, restored-generation fencing and failure-aware
bookkeeping in the canonical Backup page. The [review](reviews/2026-10-22-next-five/backup-history/README.md)
records focused checks and light/dark captures. Automatic backup lifecycle work
remains open. D12a is also integrated and host verified: encrypted alert choices,
real Android channel variants and a native OS-mute guard, with 126 focused Flutter
checks, 37 native engine checks, clean analysis and a successful Android Kotlin
compile. Physical sound/vibration delivery remains unverified. D13b is integrated:
stock details are an explicit default-off report choice, with exact chosen-source
facts in all three PDF/text templates and reviewed-capture isolation after edits.
The [review](reviews/2026-10-22-next-five/report-stock/README.md) records 86 focused
checks and theme/layout evidence. D19a is integrated: the selected locale week's
indexed recorded/skipped/voided counts follow calendar selection and active
filters, with explicit pending/error/lock states. Its [review](reviews/2026-10-22-next-five/history/README.md)
records history/motion checks and theme/layout evidence. Timing classifications
remain open. D11a is integrated and host verified: exact authored instructions
follow immutable plan versions, drafts, pause/restart, phases and shared summaries.
The [review](reviews/2026-10-22-next-five/plan-instructions/README.md) records 118
focused schedule checks and the resolved summary-fixture hang (14 checks).
All five packages are integrated and host verified. Final verification passed
113 combined feature/framework/motion checks, clean project analysis, 37 native
reminder engine checks, Android Kotlin compilation and the real Secret Service
Linux boot/persistence/navigation/export/backup flow. The Linux debug bundle
built successfully. See the [batch evidence](reviews/2026-10-22-next-five/README.md).
Device/release gates remain open. Plan-instruction output mapping is separate
from this private in-app slice; the subsequent D11b work below adds it through
explicit saved action/version links.

## Next four-task batch

Owner authorised four concurrent tasks on 22 October 2026, after the previous
five-task batch was pushed as `37a46f1`:

- D16b: whole-collection event status filters and counts, assigned to free
  DeepSeek V4.1 Flash through OpenCode.
- D17b: latest lab values beyond the 75-record/60-marker projection, assigned
  to paid `deepseek/deepseek-flash` through the direct DeepSeek API.
- D18b: prior panel comparisons beyond the 50-record window, assigned to a
  second paid direct-API DeepSeek worker.
- D11b: privacy-selected report/export instructions from the immutable plan
  version explicitly linked to a saved action, implemented by the lead.

All three workers started concurrently alongside the lead, in isolated
worktrees based on the pushed checkpoint. Acceptance criteria, ownership,
required skills and delegation identities are retained locally under
`.scratch/vital-implementation/next-four-2026-10-22/`. Each slice remains in
progress until its implementation, integration and relevant verification pass.
All four slices are now integrated and host verified. Their focused review
records are linked from the [batch evidence](reviews/2026-10-22-next-four/README.md).
Lead review corrected filtered-page clamping, reload/unlock refresh, fixed-size
marker paging and comparison ambiguity. Final verification passed 144 combined
feature/framework/motion checks, clean analysis and the Linux debug build with
real Secret Service boot, encrypted persistence, navigation, export and backup.
Physical-device and release gates remain open.
Timing tolerance, reminder follow-ups, automatic backup lifecycle and physical
device gates retain their existing open status.

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

D06 now implements real weekly browsing, selected-day reads and configurable favourites. Earlier unavailable previews have been replaced with those real capabilities. The recorded section now expands to the existing history controls. The unrelated blood-pressure preview has been removed from Today; existing supporting records remain available in their own collection. The refill card shows an existing stock notice when available and opens real stock management; a days-of-stock forecast remains D14. Whole-collection status filters (D07) and the remaining screen rollout (D23) are host implemented; measured glass (D24) remains open.

See the [native light/dark screen review](reviews/2026-10-21-stitch-rebuild/README.md). Host checks do not close physical-device gates.

## Remaining screen rollout

The owner approved the closer Dashboard/Substances layout (`466d638`) and authorised each DeepSeek Flash reviewer to move into implementation. All ten remaining screen purposes were reviewed against their saved PNG and HTML; implementations use one canonical screen per purpose, not separate light/dark or mock-only variants. Workers use isolated worktrees; the lead owns the shared foundation and verifies each integration. Local review/task evidence is under `.scratch/vital-implementation/screen-plan-2026-10-21/`.

| ID | Screen and canonical route | Live wiring / missing design sections | State |
| --- | --- | --- | --- |
| S00 | Shared components | One typography/palette/geometry source and surface/control renderer behind existing Vital and Stitch APIs. Existing fields, notices, badges, icons and page shells remain reusable. Preserve the approved Dashboard/Substances compositions. | Integrated; 63 focused checks and analysis passed |
| S01 | Create, `/create` | Real catalogue/custom identity, type/unit/product choices and durable Save. Schedule/stock require the saved item identity: use existing editors, with truthful save-first states; no nested draft controllers or invented atomic setup. | Integrated; 59 focused checks and analysis passed |
| S02 | Record, `/record/:id` and correction mode | Restyle the existing DoseForm with sheet geometry. Preserve actual time/DST, exact amount/unit, stock/strength/source/product/site controls, recovery and return/Undo. Exact presets and a guarded modal sheet are implemented under D09; unsupported context/vitals previews are removed. | Integrated; 70 regression checks, 5 visual/safe-area checks and analysis passed |
| S03 | Schedule, `/schedule/:id` | Keep all six real modes, calendar/interval/block sections, pause/phase links, reminders and Preview then Save. Missing requirement/tolerance/follow-up rules are previews. | Integrated; 44 regression checks, 7 visual/safe-area checks and analysis passed |
| S04 | Stock, `/stock/me` | Real container balances, notices, source labels, Adjust/restock/waste/measure and Add. Forecast/capacity/lot/expiry/scanning stay explicit gaps under D13–D15. Never use an ambiguous bare +/- stock mutation. | Integrated; 39 regression checks, 5 visual/safe-area checks and analysis passed |
| S05 | Events, `/events` | Real event creation/detail/configuration/revisions, memberships, dates and end review. Show factual date progress, not adherence; unresolved dates get their own review state. Counts/filters explicitly describe the loaded page when incomplete. Notes and whole-event recorded/skipped counts need storage/query support. | Integrated; 33 regression checks, 12 final UI checks, 5 framework checks, loaded captures and analysis passed |
| S06 | History, `/history` | Owner’s 21 October replacement: month calendar, compact selected-day cards, disclosed filters/tools and monthly PDF report selection. Existing cursor/anchor/source/correction/exports stay connected. Inline Undo remains on `/recorded`. | Integrated; calendar revision verified with focused UI, regression, light/dark and safe-area checks |
| S07 | Labs, `/supporting` | Restyle existing supporting records, panels, observations and trends; keep Add/detail/files/source/reports live. Latest values use a live bounded window of 75 dated records and 60 markers, with exact comparable previous values. Original dates, units, ranges and flags stay visible; no invented risk/optimal/causal labels. | Integrated; 64 regression checks, 7 final UI checks, 5 framework checks, loaded light/dark captures and analysis passed |
| S08 | Panel detail, `/supporting/me/:id` | Original values/units/source ranges/flags, dates, revisions, Edit/Void/Restore, attachments, trends and source versions. Resolve linked record names. Stored file hashes are not proof of a verified complete ledger; FHIR remains D22. | Integrated; 60 regression checks, 2 loaded capture checks, 5 framework checks and analysis passed |
| S09 | Settings, `/settings` | One hub using real capability-gated Profile/Appearance/Privacy/Reminders/Reports/Exports/Backup/Restore/Help routes. Preserve their existing forms and controls. No cloned appearance/wipe/backup workflows or fabricated counts/auto-backup claims. Shared shadcn rows keep keyboard and accessible activation. | Integrated; 74 regression checks, 8 hub/capture checks, 5 framework checks and analysis passed |
| S10 | Substance overview, `/substance/:id` | Reshape the existing unified overview: Record/Combine, per-plan Edit, stock, recent use, history and context links. Missing identity editing/refill/notes/forecast controls are truthful previews, not new duplicate detail pages. Overview/Schedule/Stock/History are real PageView sections with independent retained content. | Integrated; 49 regression checks, 18 final overview checks, 5 framework/capture checks and analysis passed |

History now follows the owner’s [replacement calendar reference](references/2026-10-21-history-calendar/README.md). Other rows use the corresponding current export in the [snapshot index](stitch/2026-10-20/README.md); S10 also uses the saved earlier substance-detail reference where no current overview export exists. Mislabelled generated headers are corrected to the real destination. Other existing utility/editor routes inherit the foundation and receive the route-capture sweep; they do not get alternative mock implementations or a fifth dock destination.

Acceptance for every screen: loaded light/dark captures; white light canvas and green-black/mint dark surfaces; 320/390/430 px plus 2× text; fixed existing dock and device/keyboard safe areas; no accidental action/quantity wrapping, clipped names or overflow (deliberate stacking/scrolling for narrow/large text); 48 px targets; real actions retain draft, lock, stale/revision, exact-unit, stock and Undo guards. Add no dependencies; the 23 October owner direction enables selected family glass while measured acceptance remains open. Extend shared components instead of copying local colours, text scales, borders or button skins. Existing D06–D24 capability gaps stay open until their actual behaviour is implemented.


All S00–S10 screen integrations completed on 21 October 2026. Final host verification passed 1,855 Flutter tests with one existing opt-in skip, clean analysis, the 34-route light/dark sweep, real Secret Service Linux boot, Linux debug build and Android debug APK build. The [rollout review](reviews/2026-10-21-screen-rollout/README.md) contains committed screenshots and per-screen evidence. Android release signing and physical-device accessibility, delivery and measured-performance gates remain open. Partial D08/D09/D16–D20 entries above identify features that screen styling did not implement.

## Next feature batch

Owner authorised three feature implementations, two by DeepSeek and one by the lead. The dependency-ready batch is D06, D07 and D09; D08’s larger combined setup/notes work remains open.

- D06, DeepSeek: real week/day navigation and factual planned/recorded/skipped summaries; durable configurable PRN favourites; existing recorded section and Undo remain reachable. Past/future browsing does not silently record a current dose against another date.
- D07, DeepSeek: whole-collection status filters/counts composed with name/type search and paging; paused, as-needed, mixed and unscheduled cases are explicit. Plan status is distinct from substance type.
- D09, lead: exact amount presets drawn from saved plans or user-entered quantities; preserve full units, stock/strength previews, manual entry and durable form safeguards. Presets never imply dose advice or save without review.

D06, D07 and D09 are host integrated and verified. The combined check found and fixed cancellation of a loading status query when filters or minute boundaries change. A targeted cancellation regression now passes. Each requires regression checks, light/dark and narrow/large-text verification, shared controls and accurate incomplete/error states before integration. See the [feature review](reviews/2026-10-21-feature-batch/README.md).


## Interaction standard

The owner approved the [interaction blueprint](interaction-blueprint.md) as the editable standard for existing and future screens. Its [rollout plan](interaction-implementation-plan.md) covers shared motion, persistent root and section paging, real guarded recording sheets, calendar paging, dialogs, anchored filters, contextual menus and reduced motion. Shared implementation, focused checks, captures, analysis, native boot and the debug APK are complete. The owner stopped the final whole-suite run to publish the first development prerelease immediately; the review records that limit. No remaining roadmap capability is marked complete solely by this presentation work.


## Current feature assignments

Owner authorised the next two tasks on OpenCode’s free DeepSeek model and a third task by the lead. D08 (guided substance setup/instructions/notes) and D10 (dose context/skip reasons) are assigned to isolated DeepSeek V4.1 Flash Free agents. The lead owns D20’s live Settings data summary and report date shortcuts. D20 is complete on the host with 56 focused Settings/design/store checks and clean analysis; [review and captures](reviews/2026-10-21-next-features/README.md). D08 is host integrated with reviewed light/dark captures and focused setup/migration/restore checks. D10 is host integrated after free DeepSeek repair and lead verification: 89 focused checks cover skip outputs, full encrypted metadata restore and legacy retry/draft compatibility. Each package retains the shared interaction blueprint, mandatory skill reads and focused data/UI/privacy verification. D11 behaviour decisions and native/device gates remain separate. Assignment does not mark a feature complete.

## Five-feature batch, 22 October

Owner authorised five tasks using free DeepSeek, paid DeepSeek and the lead, with lead takeover on rate limits and a final push. Paid DeepSeek owns D13 then D14 (dependency order); free DeepSeek owns D17 then D18, sharing the lab presentation/comparison model. The lead owns D16 event notes and whole-event summaries. These are implementation assignments, not completion claims. Local acceptance briefs and task identities are retained under `.scratch/vital-implementation/five-features-2026-10-22/`. Each package keeps the interaction blueprint, shared controls, durable guards and focused verification; native/device release gates remain open.

D16, D17 and D18 are host verified in this batch. The free lab lane hit its rate limit; the lead recovered its unfinished source changes and completed both lab packages. Comparisons exclude future, same-day ambiguous, voided and incompatible results; graph lines break at unavailable or incompatible points. See the [five-feature review](reviews/2026-10-22-five-features/README.md). D13/D14 are also integrated and host verified after paid DeepSeek implementation and lead review.

All five packages in the 22 October batch are integrated. Lead integration passed 119 focused checks, followed by 65 regression checks for final stock/data/export/draft changes and two explicit history/retry checks. Static analysis and a real Secret Service native Linux boot passed. The forecast starts tomorrow and excludes today’s remaining planned use; inventory counts disclose their 2,000-container bound. PDF stock provenance, native refill delivery/scanning, physical-device accessibility and measured performance remain outside this batch. The [review](reviews/2026-10-22-five-features/README.md) records these limits and the existing lab projection bounds.

## Substance properties, 22 October

The owner approved these capabilities before further feature expansion. They
extend the existing Create, Details, Stock and Record screens, with no duplicate
editors or clinical predictions. See [behaviour](substance-properties.md).

| ID | Capability | Acceptance | State |
| --- | --- | --- | --- |
| D25 | Guided substance forms | Taken as separates Injectable, Oral and Other from category. Secondary choices include oil/water/powder to mix and tablet/capsule/liquid/powder. Optional labelled strength per ml or tablet/capsule uses explicit mg or micrograms. Original catalogue wording remains intact. | Implemented; host verified |
| D26 | Individual mixed vials | Save original powder amount/unit and confirmed final volume, optional liquid/amount added/date, exact concentration, live dose equivalents and immutable per-dose/per-movement snapshots. Different vials may have different strengths. Preserve unknowns, legacy records, drafts and backup restoration. | Implemented; host verified |
| D27 | Optional half-life | User-entered hours/days, formulation/route context and source. Blends keep separate ingredient values. Editable reference information without inferred defaults or estimated level charts. | Implemented; host verified |

D25–D27 host evidence: [substance property review](reviews/2026-10-22-substance-properties/README.md). Physical-device gates remain open.


## Functionality batch, 22 October

The owner requested another functional batch, deferring the broader UI redesign,
and a friendly README explaining the project's safety-minded purpose.

- D15a: opt-in native Android low-stock notices for configured containers, one
  durable alert episode, existing reminder reconciliation and private Open-only
  actions. Paid direct-API DeepSeek implemented it; lead review fixed posted
  Open authority, immutable deferred deadlines and stale preference writes.
  Eight pending native slots remain separate from dose/event capacity. Schema
  26 upgrades preserve records with alerts off. Device delivery stays a separate
  evidence gate; evaluation is foreground/repair-driven. Scanning is backlog.
- D19b: factual monthly routine activity is integrated using full calendar
  aggregates and active History filters. Free DeepSeek reached its usage limit;
  the lead recovered, finished and verified the work. Counts describe entries,
  recorded days and explicit skips/voids. The collapsed summary reads counts
  only when opened, refreshes after edits and hides stale/locked data. No
  adherence, streak, lateness or missed-dose inference. Tests cover more than
  50 entries, combined entries, partial ranges/DST, boundary months, live
  corrections/Undo, keyboard, both themes and narrow 2x text. Thirty-five
  activity/week/motion checks and 27 activity/mobile regressions passed.
  A shared reveal fix lets collapse finish before pausing content tickers.
- D26b: captured actual-dose strengths and exact equivalents now appear in all
  three PDF/text report templates. Mixing details follow the stock-details
  choice; current defaults never rewrite historical use. Unknown strengths and
  unresolved replacements produce no equivalent. Host verified with 38 focused
  checks and all rendered pages reviewed; see [report evidence](reviews/2026-10-22-function-batch/report-strengths/README.md).
- README: GLM5.3Flash Free produced the reader-focused draft. Lead review
  corrected current/planned claims and retained contributor instructions.

All four slices are integrated. Final host checks are recorded in the
[batch review](reviews/2026-10-22-function-batch/README.md). Briefs and identities are retained
under `.scratch/vital-implementation/function-batch-2026-10-22/`.

## Today simplification, 22 October

Owner-directed D01 revision: left profile control and named local-time greeting,
independent week browsing/day selection, one compact daypart timeline and quiet
empty groups. Removed the progress row, week summary, duplicate next-dose hero,
Recorded block and Manage block. Unplanned medication has day-specific records,
an information dialog and a shared quick-entry sheet for existing or minimal
new medicines. Plan continues into the existing schedule editor. Name/form
edits apply to future records while saved doses retain their snapshots.
Observations stays a Coming soon preview by explicit owner request; its working
detailed editor remains available through its existing routes.
The [blueprint](interaction-blueprint.md) and
[review](reviews/2026-10-22-dashboard-simple/README.md) define the new composition
and record verification limits. This UI revision does not close device gates
or unrelated feature backlog.

The owner subsequently approved the framed dashboard reference, with Schedule
wording and a stationary calendar frame. The shared surface/control foundation
and reusable section/empty-slot components now supply that treatment. Contextual
Plan actions retain the day and suggested time through medicine selection or
creation; the existing schedule preview/save remains mandatory. See the
[Schedule implementation](reviews/2026-10-22-dashboard-schedule/README.md).

The final dashboard refinement removes the calendar footer/divider, adds
borderless daypart status chips and plus-only empty insets, and uses matching
Plan/Add commands. Unplanned records show only full name and exact amount;
all existing correction and guarded entry flows remain connected. See
[current dashboard evidence](reviews/2026-10-22-dashboard-refined/README.md).

## Five direct-API tasks, 22 October

Owner authorised four direct DeepSeek workers and the lead for five concurrent
implementation slices, based on `0dab613`. All four workers use OpenCode's
`deepseek/deepseek-flash` direct API model in isolated worktrees.

| Slice | Outcome | Owner | State |
| --- | --- | --- | --- |
| D13d | Whole-inventory Expired/Expires today filters and counts, using real local dates | DeepSeek | Host verified |
| D14c | Conditional stock forecasts for fixed-planned elapsed intervals | DeepSeek | Host verified |
| D17c | Open exact lab trend points in their original saved records | DeepSeek | Host verified |
| D21b | Factual last-confirmed-backup status in Settings Data | DeepSeek | Host verified |
| D13e | Guided choice between a new physical pack and adding to an existing container | Lead | Host verified |

These extend existing features without defining clinical timing tolerance,
follow-up policies, automatic backup destinations/retention, scanning formats or
FHIR mappings. Those decisions and physical-device gates remain open.

All five slices are integrated. Lead review aligned stock-card expiry labels
with the filter's captured day, hid retained inventory during loading/errors,
bounded interval expansion before allocation and checked source-link identity.
See the [batch evidence](reviews/2026-10-22-next-five-direct/README.md).

## Further five tasks, 22 October

The owner authorised the same four direct DeepSeek workers plus lead pattern.
These scoped extensions follow `2b283a5`; clinical timing, automatic backup,
scanning, FHIR and physical-device gates remain open.

| Slice | Outcome | Owner | State |
| --- | --- | --- | --- |
| D13f | Filter stock by an explicit inclusive expiry cutoff | DeepSeek | Host verified |
| D18b | Open the original earlier lab record from a panel comparison | DeepSeek | Host verified |
| D16c | Prepare an event-specific report in the existing report editor | DeepSeek | Host verified |
| D19c | Jump directly to an exact date in History | DeepSeek | Host verified |
| D14d | Inspect exact projected quantities and forecast assumptions | Lead | Host verified |

Every slice retains the canonical screens, shared controls, copy and motion
standards, exact records and guarded actions. Worker results require lead
integration and meaningful host verification before the state changes.

All five extensions are integrated and host verified. Lead review also fixed
adaptive filter-sheet opening/teardown, matched inventory headings, History
confirmation guards and explicit partial event ends. See the
[batch evidence](reviews/2026-10-22-more-five/README.md). Device and unresolved
product-policy gates remain open.
