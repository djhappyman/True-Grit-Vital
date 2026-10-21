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
| Today `/today` | Root page; week pager, next action, compact timeline and collapsed recorded section. Favourites configure in a focused task overlay. |
| Substances `/substances` | Root page; search and compact cards. Name/type/status queries stay store-backed. Filter popover, selected chips and contextual management menu. |
| Events `/events` | Root page; compact factual summaries, status filtering and per-event overflow commands. |
| History `/history` | Root page; month pager and selected-day cards. Filters in popover/adaptive sheet, dates in a picker, report/export tools in contextual actions. Preserve scoped/anchored links. |
| Overview `/substance/:id` | One screen with Overview/Schedule/Stock/History PageView sections. Full identity, Record and essential stock warnings remain prominent. |
| Record `/record/:id` | Modal task sheet using the same durable form. Amount/presets, time, relevant source/consequence and Save initially visible. |
| Correct `/correct/:id` | Same sheet in correction mode; retain original source/strength/revision and required physical-correction choices. |
| Combined `/combined/:person`, `/combined/:person/edit/:action` | Expanded recording sheet, complete per-source identities/quantities, original atomic command and correction/Undo guards. |
| Saved `/recorded` | Concise confirmed result with existing Undo/inspection. Preserve the canonical receipt route and return context when finishing a sheet. |
| Source `/history-source/:kind/:id` | Read-only detail sheet for ordinary records/actions; complex grouped/source comparisons remain spacious. Correction and audit trails stay reachable. |
| Item history `/item/:id` | Full history surface with contextual filters, files and use-period actions. Preserve legacy overview/history links. |
| Substance setup `/create` | Full editor; current catalogue/custom flow and draft protection. Group advanced identity/product configuration contextually. |
| Catalogue, type selection and source pickers | Anchored compact choices or focused searchable task overlay; full identities and whole-collection search. |
| Types `/types/:person`, `/types/:person/edit` | Management page; create/rename short values in dialogs. Filter controls link to management as a secondary action. |
| Schedule `/schedule/:id` | Full editor; six modes and Preview/Save guards. Conditional sections reveal smoothly and retain controllers. |
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
| Settings `/settings` | General/Privacy/Data PageView sections using existing real destinations. |
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
