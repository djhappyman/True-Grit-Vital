# Interaction rollout plan

Owner authorised 21 October 2026: finish D06/D07/D09, verify and push; then implement the [interaction blueprint](interaction-blueprint.md) across the app, build a debug APK, push and publish the first GitHub development prerelease with the APK attached. This plan tracks execution. The blueprint remains the editable standard for future screens.

## Ordered work

| Step | Scope | Acceptance | Status |
| --- | --- | --- | --- |
| M00 | Feature baseline | Review both DeepSeek results, integrate with exact dose presets, regenerate localisation, verify combined features and push a clean checkpoint. | Completed: pushed `760eb4e` |
| M01 | Shared motion and presentation | Central tokens; reusable route, sheet, disclosure, menu/popover and tab adapters; respect system/app reduced motion, focus and privacy. Existing Vital/Stitch APIs share the implementation. | Completed; see motion review |
| M02 | Root navigation | Persistent Today/Substances/Events/History PageView, dock/route synchronisation, retained per-tab state, nested gesture priority and Back/deep-link checks. | Completed; see motion review |
| M03 | Dose workflows | Record/correct/combined use actual guarded modal task sheets; concise initial content, relevant source/consequence, optional disclosure and complete dismissal handling. | Completed; see motion review |
| M04 | Calendar paging | History month and Today week PageViews change actual period queries; accessible controls, stable geometry and selected-date semantics. | Completed; see motion review |
| M05 | Screen simplification | Migrate every screen group below to its assigned presentation; use existing shared components and retain real commands/context. | Completed; see motion review |
| M06 | Combined verification | Full tests/analysis, native boot, light/dark captures, narrow/large text, keyboard, paging/interruption/dismissal and reduced-motion checks. | Analysis, focused tests, captures, native boot and APK passed; final full run stopped by owner for publication |
| M07 | First development prerelease | Build debug APK, verify metadata/checksum, commit changelog bullets, push, tag and publish GitHub prerelease with APK, checksum and accurate known limits. | Completed: [`v0.1.0-alpha.1`](https://github.com/djhappyman/True-Grit-Vital/releases/tag/v0.1.0-alpha.1), source `c10a62e` |

Use explicit evidence and commits for each completed step. Screens remain canonical; adapting presentation does not create a second mock implementation. Add no dependencies or tool upgrades for this rollout. Preserve existing record/draft/lock/operation engines.

## Existing screen matrix

| Screen / existing paths | Target presentation and visible content |
| --- | --- |
| Today `/today` | Root page; left profile and named greeting, independently browsed week pager, one daypart timeline, Plan action, day-scoped Unplanned medication and the owner-requested observation preview. No progress/week-summary/duplicate hero/Recorded/Manage blocks. |
| Substances `/substances` | Root page; search and compact cards. Name/type/status queries stay store-backed. Filter popover, selected chips and contextual management menu. |
| Events `/events` | Root page; compact factual summaries, status filtering and per-event overflow commands. |
| History `/history` | Root page; month pager and selected-day cards. Filters in popover/adaptive sheet, dates in a picker, report/export tools in contextual actions. Preserve scoped/anchored links. |
| Overview `/substance/:id` | One screen with Overview/Schedule/Stock/History PageView sections. Full identity, Record and essential stock warnings remain prominent. |
| Quick entry `/unplanned` | Searchable task sheet reusing the existing ItemForm and DoseForm. Create a minimal identity, record with explicit amount/unit/date, edit details later. Plan selection continues into the canonical schedule editor. |
| Record `/record/:id` | Modal task sheet using the same durable form. Amount/presets, time, relevant source/consequence and Save initially visible. |
| Correct `/correct/:id` | Same sheet in correction mode; retain original source/strength/revision and required physical-correction choices. |
| Combined `/combined/:person`, `/combined/:person/edit/:action` | Expanded recording sheet, complete per-source identities/quantities, original atomic command and correction/Undo guards. |
| Saved `/recorded` | Concise confirmed result with existing Undo/inspection. Preserve the canonical receipt route and return context when finishing a sheet. |
| Source `/history-source/:kind/:id` | Read-only detail sheet for ordinary records/actions; complex grouped/source comparisons remain spacious. Correction and audit trails stay reachable. |
| Item history `/item/:id` | Full history surface with contextual filters, files and use-period actions. Preserve legacy overview/history links. |
| Substance setup `/create` | Full editor; current catalogue/custom flow and draft protection. Group advanced identity/product configuration contextually. |
| Catalogue, type selection and source pickers | Anchored compact choices or focused searchable task overlay; full identities and whole-collection search. |
| Types `/types/:person`, `/types/:person/edit` | Management page; create/rename short values in dialogs. Filter controls link to management as a secondary action. |
| Schedule `/schedule/:id` | Simple amount/time/repeat/duration editor with Review/Save guards. Unusual modes and breaks live under More options. Compatible-unit equivalents update live; date ranges use the canonical calendar. |
| Pause `/pause/:id` | Focused task overlay; preserve exact interval scope and explicit resume/review controls. |
| Phases `/phases/:id` | Full editor/review for repeating breaks and consequential boundaries. |
| Stock `/stock/:person` | Compact inventory page; exact balances/states, Add and per-container overflow. |
| Container `/stock/:person/create` | Full editor for product/strength/opening context and validation. |
| Stock adjustment `/stock/:person/adjust/:container` | Guarded sheet for one adjustment/restock/waste/measure task, with exact unit/consequence and reason. |
| Product label `/products/:person/label/:item` | Full editor/review, complete ingredient and source identity. |
| Site `/site/:person/:record` | Short guarded editor in a dialog/adaptive sheet. Preserve revision/source ownership. |
| Event create/edit `/event-create`, `/event/:id/edit` | Full editor; dates, memberships and consequences grouped around the task. |
| Event detail `/event/:id` | Detail page; identity, factual dates/progress and memberships initially. Revisions/configuration/record tools in overflow. |
| Event decision/review `/event/:id/decision`, `/event/:id/review` | Full consequential review; exact per-item proposals and explicit choices remain visible. |
| Event/period revisions `/event/:id/revisions`, `/period-revisions/:id` | Read-only full audit pages with shared route motion. |
| Use periods `/use/:person/:item`, `/use/:person/:item/edit` | History page and guarded editor; concise summaries, contextual edit/revision actions. |
| Labs `/supporting` | Collection page with factual latest values and compact records; filters in popover/adaptive sheet, active scope visible. |
| Lab/observation add/edit `/supporting/:person/add-panel`, `/supporting/:person/add-observation`, `/supporting/:person/:id/edit` | Full transcription editor; values/units/original ranges and source dates remain explicit. |
| Panel `/supporting/:person/:id` | Result-focused page; source details, linked context, revisions and stored hashes behind appropriate disclosures/actions. |
| Trends `/supporting/:person/trends` | Full comparison view; selections in local controls; chart gestures own their region. |
| Charts `/charts` | Full analytical page with scoped controls, table alternative and source return context. Preserve keyboard inspection. |
| Files `/files/:person/:kind/:target` | File collection; compact records and contextual commands. |
| Rename file `/attachment/:id/rename` | Short dialog/adaptive sheet; preserve attachment identity and revision guard. |
| File viewers `/attachment/:id`, `/supporting-source/:person/:id` | Full protected viewer; existing lease/privacy/integrity checks. |
| Record revisions `/revisions/:id` | Full read-only audit trail with exact version/source context. |
| Reports `/reports`, `/reports/preview` | Full selection and preview workflow; dates, inclusion/privacy and exact reviewed artifact remain explicit. |
| Export `/exports` | Full selection/review; scope and concrete destination remain visible before generation. |
| Backup/restore `/backup`, `/restore` | Full guarded workflows. Never persist passwords; show concrete progress/consequences and recovery. |
| Settings `/settings` | Navigation rows beneath the profile header; no inline data summaries or report controls. Group links reveal section anchors. |
| Local data `/settings/storage` | Existing locked-aware data summary in the shared settings drilldown. |
| Appearance `/appearance` | Settings page using shared switches/choices and central reduced effects. |
| Profile `/profile` | Full short setup/profile editor; keep adult confirmation and report identity explicit. |
| Reminders `/reminders` | Settings page with truthful OS/capability state and recovery. |
| Reminder action `/reminders/action/:id` | Guarded contextual action surface; authentication, stale envelope and source checks stay intact. |
| Privacy/diagnostics/help `/settings/privacy`, `/settings/diagnostics`, `/settings/help` | Focused pages with short summaries; detailed diagnostic/source information disclosed. Destructive decisions use dialogs. |
| Licences `/settings/licences`, `/settings/licences/app`, `/settings/licences/:index` | Full readable lists/detail pages. |
| Recovery, locked, missing and unavailable states | Existing gated surfaces; privacy hides immediately, recovery actions remain keyboard-accessible. |
| Redirects `/`, `/scope`, `/people*`, `/person-history/:id` | Preserve valid single-user destinations. No duplicate screens or reintroduced person selection. |

## Release evidence

Final notes use a plain-English changelog and identify the exact commit, APK file, application/version metadata and SHA-256. Check for existing tags/releases before choosing the first tag. Publish the APK as an explicitly labelled development prerelease; production release signing remains separate. Verify the uploaded release assets after publication. Preserve the canonical blueprint and final captures in the repository; remove only known task-owned duplicate/intermediate renders after verification.

## Substance property extension

D25–D27 (22 October) extend the existing Create/Details/Container full editors
and Record task sheet. Conditional route/form choices and optional half-life or
mixing details reuse shared controls/disclosures. The live dose equivalent sits
beside the amount; source selection and saved snapshot identity remain explicit.
No new route or alternative mock editor is introduced. See
[substance properties](substance-properties.md) for the field and history rules.

## Monthly activity extension

D19b adds a collapsed Routine activity summary to canonical History. It uses
the browsed month and existing filters, with shared surfaces, controls and
reveal motion. No new route is introduced. Counts load when opened; query,
dataset and lock changes hide retained values. Keyboard activation and
collapse geometry, both themes and 320/390/430 px at 2x text are covered by
`test/history_routine_activity_test.dart`.

## Today simplification, 22 October

The owner replaced the earlier Today composition with the current blueprint.
Week drags browse without selecting Monday or refreshing the selected day.
Empty days keep three quiet dayparts; populated days show only used groups.
The new chooser reuses the durable creation/recording engines and shared task
frame. Medicine identity edits preserve historical dose snapshots. Observations
remains a Coming soon preview without an entry action by explicit owner choice.
See [dashboard evidence](reviews/2026-10-22-dashboard-simple/README.md).

The subsequent framed Schedule revision follows the owner’s new reference:
shared bordered surfaces, daypart cards with contextual Plan actions, a compact
observation preview, and a stationary calendar frame whose dates alone page.
Morning/Afternoon/Evening planning seeds a visible suggested time; the existing
preview, draft, lock and command guards remain authoritative.
See [Schedule review](reviews/2026-10-22-dashboard-schedule/README.md).

The final refinement removes the calendar footer/divider, puts borderless status
chips on each daypart title, replaces empty text/actions with a quiet centred
plus, and pairs one outlined Plan button with a matching Add button beneath
compact unplanned records. See [current evidence](reviews/2026-10-22-dashboard-refined/README.md).

## Guided restock

D13e adds `/stock/:person/restock/:container` as a contextual task sheet. It
replaces itself with the canonical new-container page or quantity-adjustment
sheet, preserving the existing draft and save guards. The chooser never writes
stock and copies no pack facts. [Host evidence](reviews/2026-10-22-next-five-direct/restock/README.md).

## Inventory and source inspection

D13d adds Expired/Expires today choices to the existing inventory filter
disclosure. Counts and card labels share the observed civil day; an unknown
zone has an explicit unavailable state. D17c adds an Open action beside each
exact lab trend value, retaining the existing saved-record detail and filtered
Labs return location. D21b replaces the duplicate Settings Data Backup command
with a compact receipt-based status and the same destination. Shared controls,
lock handling and disclosure motion remain in use. Both themes, narrow layouts
and host navigation are covered in the
[batch evidence](reviews/2026-10-22-next-five-direct/README.md).

## Forecast inspection

D14d uses the existing stock forecast's shared Details disclosure. Exact totals,
inclusive dates and the resolved plan zone appear only after complete
calculation; unsupported results expose no partial totals. The initial forecast
keeps its conditional basis visible. Lock hides the expanded quantities, and
the shared disclosure supplies focus and reduced-motion behavior.
See [host evidence](reviews/2026-10-22-more-five/forecast-details/README.md).

D18b adds a contextual Open action to the earlier lab comparison, using the
existing saved-panel detail and nested return context. The source is available
only for a uniquely found earlier result. Current panel filters stay mounted
through inspection. [Host evidence](reviews/2026-10-22-more-five/prior-source/README.md).

D19c adds a compact Date command to the existing History calendar tools. Its
shared dialog changes only the browsed day on explicit confirmation, preserves
filters and shows the effective day-bound zone. Cancel/Escape/Back restore
focus; lock or a changed zone prevents a pending date from applying.
[Host evidence](reviews/2026-10-22-more-five/d19c/README.md).

D13f adds an explicit inclusive expiry cutoff inside the existing inventory
filter disclosure, with a full-date active chip and reset. Lead review also
fixed the shared adaptive sheet: its custom controller now starts the opening
animation, and teardown does not complete a closed overlay twice. Direct
320 px/2x entry, keyboard insets, reduced motion, reopening and all four
collection filter destinations are host checked.
[Evidence](reviews/2026-10-22-more-five/d13f/README.md).

D16c adds Report to canonical event detail. It opens the existing report editor
with a named event and visible date/template selection. A different active
selection needs explicit Replace; busy work and lock remain guarded. Partial
entered ends block the shortcut instead of becoming an ongoing-date estimate.
[Host evidence](reviews/2026-10-22-more-five/event-report/README.md).

## Inventory order and backup receipts

D13g adds an explicit Name/Expiry choice to existing inventory options. Sorting
precedes paging, with undated containers last and the existing incomplete-read
warning retained. Lead integration repaired shared option-surface keyboard focus:
Escape now closes narrow sheets and restores the invoking control, tested across
Stock, History, Substances and Labs. D21c keeps Backup receipt inspection inside
the existing disclosure, with shared filter segments and separate creation/check/
save dates. Settings and Backup share the latest confirmed-save calculation.
See [batch evidence](reviews/2026-10-22-third-five/README.md).

D20b adds Report to the existing substance overflow and seeds the canonical
Reports editor with one exact item. The existing editor remains reviewable;
its context notice follows the actual selected items. Invalid item/date links
retain recovery instead of broadening the report, and another active selection
needs explicit Replace. Keyboard entry and return to the mounted overview are
covered in the [item-report evidence](reviews/2026-10-22-third-five/reports-item/README.md).

D13h adds read-only Open commands to recorded-use stock movements. Single and
combined saved-dose identities resolve through the canonical source sheet;
movement reversals never become record IDs. Pending lookup has lock/departure
and duplicate-navigation guards, with the spinner limited to resolution. Back
retains the stock history page and underlying inventory context.
[Host evidence](reviews/2026-10-22-third-five/stock-source/README.md).

D16d adds the compact Open command beside the existing event-history preview,
using canonical History filtering and a visible event-name chip. Loading/error/
Retry affects that label only; exact ledger scope stays selected. Local return
links are checked against registered routes, and inactive History does not
capture Back after a tab switch. Existing dated membership and event bounds
retain their meaning. [Host evidence](reviews/2026-10-22-third-five/d16d/README.md).

## Fifteen-task follow-through, 23 October

Catalogue search uses the shared input with debounce and immediate Search/Clear.
Preset editing uses a short guarded dialog. Export date shortcuts leave review
and Save explicit. Stock filters remain within the existing history surface;
metadata snapshots use the shared disclosure. Trend/site sources retain their
canonical viewers and return context. Quick entry reuses the current editors
with strict route validation. Delete records retains the shared dialog, safe
initial focus and captured transaction authority. Reminder cancellation facts
remain under Details. These tasks add no screens or motion exceptions.

Host checks include both themes, narrow/large text, dismissal, keyboard and the
relevant draft/lock/navigation cases. The [batch review](reviews/2026-10-22-fifteen/README.md)
records evidence and limits; physical accessibility/performance gates stay open.

## Roadmap follow-through, 23 October

Schedule requirements and timing/follow-up choices extend the canonical editor
and its Preview/Save flow. Captured labels use the existing shared badges and
History cards; no additional screen or gesture is introduced. All timing choices
start off and neither food nor bedtime labels infer clinical intervals.

FHIR is an option in the existing Export flow, followed by mapping review and
explicit Save. Existing protected-file, Back/dismissal, lock and stale-dataset
guards remain authoritative. Both rendered themes, narrow and double text are
verified with persisted appearance and real-font captures.

Scan opens inside the existing quick medication task. Camera/manual entry,
current-identity review and Link/Use/Replace reuse shared controls and surfaces.
Route coverage, backgrounding, lock, dataset replacement and old-camera callbacks
invalidate captured authority. Return requires an explicit restart; no camera
result automatically records use or changes stock. Manual entry stays available.
Both themes and large text are host checked. The fixture-only performance tool
exercises existing paging and composition without changing production motion or
enabling glass. [Evidence and remaining device limits](reviews/2026-10-23-roadmap-finish/README.md).

## Workout family, 23 October

Shared adapters now provide Workout-style faux-glass cards, glass overlays, a transparent-to-glass app bar and a full-width bottom bar. Measured chrome insets survive branch Navigators; initial content and focus reveal clear the header, and trailing padding clears the bottom bar. Canonical page wrappers use the same adapter.

Motion tokens match Workout's active push, press, selection, disclosure and modal timings. Full pages use Cupertino push/parallax; root pages and the bottom selection share a controller. Segments move their highlight, disclosures rotate their chevron, and vertical scrolling uses the family physics. Retain existing draft, dismissal, lock, exact-quantity and revision guards. Reduced motion keeps stable route/form subtrees.

Verification: whole-project static analysis passed. A focused inset diagnostic passed before the final motion edits. The owner explicitly stopped comprehensive testing; no full regression, final capture matrix, native build or physical-device acceptance is claimed for this pass. Old capture helpers and safe-rectangle expectations require adaptation for the edge-to-edge viewport during the later test run. Production appearance is enabled by owner instruction; physical validation remains open.

## Canonical controls, 23 October

The follow-up family pass adapts Workout's canonical overlay frame/actions, pill fields and soft action rows. Vital and Stitch buttons share revised emphasis, warning/destructive tints and hover/press feedback. The shared dialog now owns explicit title/body/footer styles with a transparent shadcn ModalContainer; editor dialogs omit sheet handles. Filter/overflow triggers use VitalIconButton, and settings destinations use VitalNavigationRow. Existing callbacks, focus nodes, form controllers and guarded routes remain in place. No dependencies or fonts were added.

Reference sources: Workout's shared overlays/canonical app_overlay_frame.dart and app_overlay_actions.dart, app_overlay_models.dart, forms/app_form_fields.dart, layout/app_media_picker_components.dart, and app/theme spacing/typography/color_schemes.dart. These inform Vital adapters; sibling Material widgets are not imported into Vital.

Static analysis and hot reload passed. Comprehensive interaction, capture and device checks remain deferred by the owner's standing direction. No measured visual/accessibility acceptance is claimed from the source comparison alone.

## Settings family, 23 October

The owner requested Workout's settings styling across the hub and subpages. Shared settings toolbar/body/section/row/card/type adapters now carry that design. The hub uses one continuous list without tabs, with a centred saved-profile header, flat rows and small section labels. Group return links reveal section anchors. Appearance uses real disabled segments, flat switches and a disclosure for its existing samples. Same-choice retries after preference failures remain available.

The route-scoped presentation reaches Profile, Reminders, Privacy, Diagnostics, Help and all licence pages through the existing EntryPage/form engine. Backup, Restore, Reports/preview and Export receive matching headers and open body surfaces. Restore's active-operation Back guard, report return context, preview Save/Share, permission actions, capability gating, profile drafts and destructive confirmation authority stay on their original paths. The later navigation-only correction adds `/settings/storage` for the existing local data summary; no new setting or data capability is added.

Reference sources are Workout's settings_screen.dart, settings_group_screens.dart, settings_drilldown_scaffold.dart, settings_section_widgets.dart and settings_surface_components.dart. Shadcn remains Vital's control system. Static analysis and live hot reload were used; comprehensive interaction/capture/native tests remain deferred at the owner's request.

### Owner correction: one page and app typography

The owner rejected tabs in the Settings hub and withheld push until visual approval. The hub now follows Workout’s centred avatar/name layout and continuous section list. It has no horizontal pager. Existing Privacy/Data group links scroll to their section rather than selecting a tab.

Plus Jakarta Sans and JetBrains Mono now supply the shared app typography. Eight font files were copied unchanged from Workout, with embedded copyright/OFL metadata checked and source/target hashes matched. Font licences are bundled and available in the existing notice collection. The UI font change reaches Vital, Stitch compatibility widgets, native shadcn text and code/numeric styles. Existing PDF document-font handling is retained. This pass remains local for owner review; no push or release is authorised yet.

Local verification after the correction: whole-project analysis passed; hot reload reported no runtime errors in the running app. The Linux debug asset bundle was rebuilt successfully and its font manifest contains all four weights of both new families. The existing running process requires a full app restart to review the new font registration. No comprehensive tests, push or release were performed.

## Light surfaces, 23 October

Owner correction: light sheets/dialogs keep solid Material-style colouring. Background dimming is explicitly allowed; the sheet itself must not show the dimmed page through translucent glass. The shared surface renderer now uses solid theme colours for light overlays/chrome, while dark glass and all existing barrier/dismissal/record guards remain in place. The appearance sample follows the same policy. Verification is static analysis and live reload; comprehensive tests and publication remain deferred.

## Hub and pill refinement, 23 October

The owner requested navigation rows only in the Settings hub. Local data now opens its own subsection. Reports retains its date editor, and Backup retains its confirmed-save/history panel. The hub no longer embeds summaries, report shortcuts or backup commands. Shared segmented pills explicitly centre every label and use bold text, including matching width calculations for the scrollable large-text layout. Comprehensive tests and publication remain deferred.

## Medicine chooser, 23 October

The owner approved a compact chooser: Choose medicine, quiet Search medicines placeholder with persistent semantics, Scan beside the field, flat saved-medicine navigation rows and one quiet Create action below results. Existing full-collection search, paging, scan confirmation, stale-dataset and route/lock guards remain in place. The saved form appears only when supplied. No strength or dose is inferred from a medicine name. The shared sheet adapter no longer adds a dismiss-only Back button; its accessible handle and existing dismissal guards remain.

## Canonical pickers and Schedule, 23 October

Local implementation, awaiting owner visual acceptance. Schedule uses the simplified composition and exact compatible-unit conversion. Captured display strength and optional factual end rules extend the existing version codec. Existing drafts, revisions, generation, lock and uncertain-save guards remain in place.

Workout's canonical date, clock, navigation, range-summary and week-math sources are adapted in `lib/ui/pickers`; see [provenance](picker-provenance.md). Active date/time entry paths now call them in recording, combined doses, Schedule, phases/pauses/intervals, stock/preparation, events/use periods, History, reports/exports, charts and supporting records. Inclusive and exclusive upper bounds retain their original domain meaning. Existing Today/History record calendars keep their actual queries and paging policies.

Repeat editors share compact selectors, weekday pills, steppers and reduced-motion-aware transitions. Monthly/yearly selectors retain explicit missing-date policy; yearly is represented by the existing exact month engine. No medication dose/strength is inferred from its name. Workout's planned occurrence-count stop is not reinterpreted as recorded medication use; Vital's requested duration/actual-amount/container rules remain authoritative.

Verification for this pass is deliberately limited to formatting, static analysis, exact arithmetic/codec/version-end checks and hot reload/runtime diagnostics. The owner deferred comprehensive tests; physical-device range dragging, focus/keyboard, largest-text and reduced-motion acceptance remain to be exercised. No commit or push is authorised for this UI pass until the owner is happy.

Host evidence for this local pass: `./tool/flutterw analyze --no-pub` completed with no issues; hot reload succeeded and Dart runtime diagnostics reported no errors. A disposable deterministic check confirmed 1ml = 400mg, 0.5ml = 200mg, inverse/microgram conversion, refusal of non-exact scheduling precision, codec snapshots and per-version end isolation. The check used synthetic strength data and did not change the owner's medicine. Its temporary runner was removed after verification. These results do not claim physical-device visual, accessibility or performance acceptance.

Schedule refinements: Times Add is a centred quiet text action; stable keyed rows spring/fade in and out using the shared animated-row adapter. Light dropdowns use the semantic inset fill. Start/end values are centred, human-readable quiet text controls. One When to take selector replaces the separate food and bedtime controls, preserving an existing combined instruction until explicitly changed. No medication timing advice or new dose defaults are introduced.

The 23 October Schedule refinement groups date/time/repeat controls in one surface, uses Starting with consistent label/value alignment, provides a multiline Instructions field with ghost label/example, and keeps the plain-English Timing controls visible above Advanced. The one Advanced expansion explains Amount per time and Scheduled days off. Existing fields, defaults and durable commands are retained; Early/On time/Late remain person-defined timing labels.

## Quick medicine strength and light controls, 23 October

Local implementation awaiting visual acceptance: grouped medicine-form dropdown; fixed one-unit reference; optional mg/microgram strength; guarded Convert dialog; and powder/final-volume entry. Caplets use the existing count pipeline. Original nonterminating label ratios are retained exactly in the profile with an additive quantity field; older profiles retain their original per-one meaning. Stock prefills use only exact representable per-one values, and mixed preparation fields retain their original mass and final volume.

Light text fields and dropdowns use the shared soft neutral grey fill (`#E7E8EA`), strengthened after the owner found the earlier fill too difficult to see. Dropdown hover remains neutral. Chip fills derive from their text tone. Dark-mode fill behaviour is retained. Static analysis, exact synthetic conversion/legacy round-trip checks and hot reload/runtime diagnostics are the scoped checks; comprehensive tests and physical-device visual acceptance remain deferred by the owner. No commit/push was made.

The owner’s 23 October medicine-entry refinement replaces the separate For row with Strength, amount/unit controls and a fixed per-one reference. Narrow or large-text layouts place that reference beneath the controls. Medicine form adds a brief explanation and simpler option subtitles. Shared grouped dropdown headings use bold accent text and extra group spacing. These changes retain the existing conversion, mixed-volume, save and dismissal paths; verification is scoped to analysis and hot reload/runtime diagnostics, with visual acceptance by the owner.

The subsequent strength refinement restores the live equivalent for all supported forms, keeps retained original label ratios visible, makes the per-one reference bold in the accent colour, and sizes the mass-unit trigger independently of the amount field. Short selected unit labels retain full menu/accessibility wording. The leave-blank hint was removed. Narrow and large-text layouts adapt using measured reference width and can stack the controls.

The final preview correction keeps both label strength per entered quantity and the per-one equivalent visible for every valid strength, with singular/plural count labels. Convert now retains original amounts for terminating ratios as well as recurring ones; derived display values do not replace label data. This reuses the existing additive profile/draft fields and exact arithmetic.

The owner’s final clarification makes the input Label strength itself: original strength and quantity remain visible and editable, including after Convert. The calculated per-one preview appears only for quantities other than one (numeric equality, so 1.0 also omits it). The former duplicated label preview is removed. This supersedes the preceding always-two-preview treatment.

## Medicine categories, 23 October

Medicine form and Category now share a two-column row with short helpers and responsive stacking. The ten agreed starter categories have brief plain-English subtitles; saved custom categories are included. Create category opens the shared glass/opaque dialog and stages the choice in the existing durable medicine draft. The existing atomic item/type command persists it on medicine save, preserving identity/revision guards and existing collection filtering. No schema or dependency changes were needed. The dialog retains lock/generation dismissal and stale-result checks. Targeted static analysis and debug bundle compilation passed. The existing running session rejected hot reload with the internal tooling error s1.reloadSources (-32603), so these category changes need a session restart for visual review. Comprehensive tests and device visual acceptance remain deferred.

## Shared form baseline, 23 October

Owner approved the New medicine hierarchy for future sheets and full-page forms. The source screenshot is retained in [the form reference](reviews/2026-10-23-form-standard/README.md). The current [blueprint](interaction-blueprint.md#form-standard) records two-column fields, selective subtitles/ghost text and shared styling. Reusable `VitalFormRow` and `VitalFormActions` back the rule. Medicine creation adopts them: Create has no decorative tick; sheets stack primary/Cancel, while full pages show equal Cancel/primary columns with measured large-text fallback. Existing durable save and dismissal callbacks remain in place. Other forms migrate when revised; this is not a claim of app-wide migration. Targeted static analysis and hot reload are the scoped checks; comprehensive tests remain deferred by the owner. All changes remain local, without commit or push.

## Approved UI checkpoint, 23 October

The owner accepted the revised medicine form and approved committing and pushing this UI checkpoint with a comprehensive changelog. This supersedes the earlier hold on publication for this pass. Full `./tool/flutterw analyze --no-pub` and `./tool/flutterw build linux --debug --no-pub` passed on the final code. Live hot reload and runtime diagnostics passed after the running compiler session was rebuilt. Font hashes match the recorded source assets and bundled OFL notices. Comprehensive tests and physical-device accessibility/performance acceptance remain deferred; this checkpoint does not publish a new APK or release.
