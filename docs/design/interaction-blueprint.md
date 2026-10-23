# Vital interaction blueprint

Version 15. Owner approved the standard on 21 October 2026, the Today simplification on 22 October, and the Workout-family glass, motion, controls and settings direction on 23 October 2026. This is the definitive presentation and motion standard for existing and future screens. Implementation status is tracked separately in the [rollout plan](interaction-implementation-plan.md); approval of this standard does not mean every screen has migrated.

Use this blueprint with the [shared components](components.md), [design references](README.md), single-user specification and mobile copy contract. The original Stitch exports remain visual evidence; the owner's later History calendar and interaction decisions take precedence. Changes to this blueprint require an explicit explanation of the changed rule and updated examples/tests. Keep one current rule rather than adding contradictory exceptions.

## Choose the presentation

| User intent | Presentation | Contract |
| --- | --- | --- |
| Visit a main destination | Persistent root page | Today, Substances, Events and History share a PageView and fixed dock. Preserve each page's state. |
| Browse peer sections | Tabs and PageView | Use for substance Overview/Schedule/Stock/History. Settings is one continuous page, without tabs. One canonical screen, with distinct content per tab. Keep the tab strip on one row; scroll it when large text cannot fit. Segmented pill labels are always centred and bold in every state. |
| Browse adjacent periods | Calendar PageView | History months and Today weeks follow horizontal dragging. Buttons provide the same navigation. |
| Complete one contextual task | Modal bottom sheet | Record/correct doses, choose sources and make stock adjustments without losing the originating context. |
| Make a short decision/edit | Dialog | Confirm destructive consequences, keep/discard unfinished work, rename, and edit a small isolated value. |
| Choose local filters/options | Anchored popover | Filtering, sorting and compact selectors appear beside their invoking control. Use a focused sheet when content cannot fit accessibly. |
| Choose a secondary command | Overflow menu | Edit, revisions, files and management commands belong in a contextual menu. Keep the primary task directly visible. |
| Complete a substantial workflow | Full page | Substance setup, schedules, lab entry, report/export selection, backup/restore and complex reviews retain enough space for explicit validation and consequences. |
| Inspect a document/history trail | Full page or read-only detail sheet | Simple record inspection fits a sheet; original files, audit trails and comparisons use their established viewers. |

Filters change a collection; they are not separate destinations. Keep name searches, active filter chips and one-action clearing visible. Opening a filter must open filtering, not an unrelated management screen.

## Keep information focused

The initial view contains identity, the current task, essential state and its primary action. Keep exact quantities, units, consequential source/strength choices, validation and pending/conflict states visible when needed to complete that task.

Move optional context into Details, More, a contextual menu or the appropriate secondary screen. Keep full provenance, source versions, checksums and audit information reachable without displaying them on every card. Keep unfinished capabilities in the roadmap. The owner explicitly requested one quiet Coming soon observation preview on Today; it has no entry action and does not open the existing detailed observation editor. A source flag/range is factual context, not permission to invent a clinical classification.

Use one scrolling owner for each visible page/sheet/tab. Each state has a deliberate loading, empty, filtered-empty, error, unavailable and locked presentation. Refresh existing data in place. Stable record keys preserve expansion, focus and scroll across updates.

## Root and nested paging

- Synchronise root PageView, selected dock item and route. Preserve independent scroll/filter/navigation state. Visiting another root destination must not recreate a form or reset its draft.
- Dock taps use a bounded transition; distant taps avoid rapidly sweeping unrelated pages past the reader. Finger-driven movement follows the gesture and settles naturally.
- Nested calendar and section pagers own horizontal drags within their bounds. Root paging handles the surrounding page. Chart panning, text selection and modal gestures retain their own interaction area.
- History uses a six-week month grid with predictable height. Preserve actual date bounds, original counts, selected-date identity and timezone semantics. Keep large-text/narrow-screen alternatives accessible, including an agenda view where a month grid cannot provide usable targets.
- Today week paging browses dates without changing the selected day or its records. A date tap selects the queried day; Today restores both the current week and day. Keep the outer calendar surface and month controls stationary. Only the date strip moves within the PageView. Omit the selected-date footer and divider; preserve pill positions and avoid rebuilding the feed on week drags. History month paging retains its existing query/selection policy. Calendar arrows and Today remain available to touch, keyboard and assistive technology.
- Hidden pages do not accept focus or announce content; suspend their decorative tickers. Preserve platform Back, deep links and return locations. Modal presentation sits above the active branch.

## Modal task sheets

Sheets are real modal overlays: visible underlying context, scrim, upper corners, a handle, bounded width and content-aware height. They may expand toward full height for large text, keyboard or longer content. Keep device insets, keyboard padding and the primary action usable.

Do not add a Back button merely to dismiss a sheet. Use the shared accessible handle, drag, outside tap, Escape and platform Back through the same safe-exit policy. A genuine internal step may retain its own navigation control.

Single-dose recording initially shows substance identity, amount/presets, actual time, relevant source and the exact stock/strength consequence, followed by Save. Existing optional fields appear under More. Multi-source recording uses an expanded sheet with complete source identities and quantities. A source chooser can be an internal sheet step with Back; avoid stacking task sheets.

Reuse the current durable form controller/command path. Every dismissal path, including scrim, drag, Escape and system Back, enters the same safe-exit policy. Keep/discard decisions preserve the draft on cancellation. A pending or uncertain write is resolved before another save or unsafe dismissal. Restore focus to the invoking control or a surviving neighbour.

Preserve record/correction deep links. A directly opened sheet receives a valid underlying destination. Confirm success only after durable commit; communicate saved/failure once and retain existing review/Undo paths. Privacy lock immediately covers the sheet and its underlying records.

## Form standard

The owner approved the [New medicine reference](reviews/2026-10-23-form-standard/README.md) on 23 October 2026 as the starting point for future sheet and full-page forms. The subsequent correction removes the tick from Create and gives full-page forms a two-column action row. Apply this hierarchy when creating or revising a form; migration of untouched forms is tracked separately.

- Start with a short task heading and one useful purpose sentence. Then show related fields, conditional calculations or quiet tools, and one primary action with Cancel. Avoid nested cards around ordinary fields.
- Use two equal columns for related fields where their content fits. `VitalFormRow` supplies shared 12px gutters and stacks for narrow layouts or larger text. Keep long free-text and instructions fields full width. Never shrink or truncate names, units or important values to force columns.
- Keep concise field headings and add a short, plain-English subtitle only when it helps explain the choice. Use shared text roles, 4px heading-to-helper spacing and 8px before the control. Keep roughly 16–20px between field groups.
- Use ghost text selectively for obvious entries such as Name and Search. Keep a persistent accessible label after typing. Meaningful quantities and relationships retain visible headings, units and useful subtitles; Amount can be a placeholder beneath Label strength. This owner-approved rule qualifies the general visible-label default.
- Keep the existing pill inputs and dropdowns, soft neutral grey light-mode fill, solid light surfaces and dark glass treatment. Selected unit controls are compact; quantity controls receive the remaining space. Derived values stay clearly distinct from entered values.
- **Sheet forms:** stacked full-width primary action, then full-width neutral Cancel, with a 10px gap. **Full-page forms:** two equal-width buttons, Cancel on the leading side and the primary action on the trailing side, with a 12px gap. `VitalFormActions` detects route-backed tasks; non-route sheet hosts pass `stacked: true`. Full-page actions may stack when measured labels cannot fit at the current text scale.
- Button labels are centred, bold and concise. Use the shared accent-filled primary and neutral secondary styles. Form footer commands are text-only; omit decorative ticks or plus icons. A genuine pending indicator may accompany Saving. Existing short decision dialogs retain their shared dialog action layout.
- Reuse shadcn controls, shared field/layout/action components and existing durable commands. Retain inline errors, keyboard and safe-area handling, focus, draft, lock, revision, pending/uncertain-write and dismissal guards. This visual standard does not alter medicine data or save semantics.

## Today composition

The profile control sits on the left of the app bar. Today uses a local-time greeting and the saved profile name. Keep the shared chrome, fixed dock and device safe areas. At large text sizes, put the greeting on its own full-width row and keep dock labels in one horizontally scrollable row, preserving space for the page and full-size text.

Use one timeline for planned doses. Group by expected Morning, Afternoon and Evening; show Night or No set time only when needed. With planned entries, omit empty groups. With none, show the three daytime headings and quiet inset empty states. Label this area Schedule. Place a borderless status chip on the right of each daypart title: Empty, an exact taken/planned count, or Partial when the read is incomplete. Skipped doses do not count as taken; never invent totals. Each empty daypart uses the shared framed section component with a meaningful icon and time range. Its borderless empty inset contains only a quiet centred plus with a descriptive accessible planning label. Keep one full-width outlined Plan button beneath the timeline, including empty days. The contextual plus seeds a visible suggested time in the existing editor: Morning 08:00, Afternoon 14:00, Evening 20:00. The person reviews quantities and time before Preview/Save; no plan or dose is automatically committed. Preserve exact quantities, expected times, Taken, Skip, Snooze, Extra, Edit, Undo, incomplete calculation warnings and source/strength review through the existing row component. Do not duplicate a next-dose hero, progress row, weekly summary or separate Recorded/Manage section.

Unplanned medication means actual use without an active planned-dose action. Its information dialog explains this in plain English. Add opens `/unplanned`, a guarded task sheet containing whole-collection search, existing medicine selection or minimal creation. The shared chooser is headed Choose medicine, with quiet Search medicines placeholder text inside its search field and a persistent accessible label. Scan is a compact icon command beside search. Saved medicines appear immediately below as flat shared navigation rows, showing the full name and saved form only when supplied. Keep one quiet Create action below the results; omit a repeated explanatory sentence and stacked Scan/Create buttons. Choosing a medicine uses the existing dose editor, with the selected date visible and editable. Plan uses the same chooser and then the existing schedule editor, seeded with the selected date. Minimal creation saves a medicine identity first; the dose is a separate confirmed save. Cancelling the dose retains the medicine. Its name, form and other details remain editable in the existing Details editor; saved doses keep their original snapshots and units. Quick-create drafts retain their original day and task context.

Keep unplanned entries scoped to the displayed day, with exact actual quantities/units and correction access. Existing drafts, pending attachment jobs and consequential stock warnings remain reachable. Observations remains the explicitly requested compact Coming soon card, with no entry action. The unplanned section uses one enclosing shared surface, a plain-English subtitle and compact correction rows showing only full medicine name and exact amount/unit. Its Add command sits beneath the card and matches the full-width outlined Plan button. The [latest refinements](reviews/2026-10-22-dashboard-refined/README.md) supersede the footer, dashed empty inset and primary Add treatment in the approved [reference](reviews/2026-10-22-dashboard-schedule/owner-reference.png). Use the same semantic typography, framed surfaces and controls as the rest of the app.

## Quick medicine entry

Quick creation shows Name as ghost text inside the input pill, without a separate visible header, retaining the persistent accessible label and inline validation. This follows the selective ghost-text rule in the form standard. Use one Medicine form dropdown with Oral and Injectable groups and short plain-English subtitles. Place Medicine form and optional Category in two equal columns, each with a short helper: What it comes as. and How you group it. Stack the fields at narrow widths or larger text. Category offers ten owner-approved starter groups with short subtitles, saved personal categories and a trailing Create category command. The compact dialog selects a new name into the medicine draft; saving the medicine persists it through the existing personal-type command, making it reusable. Cancel changes nothing. Categories organise/filter records and do not assign clinical classifications or change doses, strengths or schedules. Shared grouped dropdowns give each group a bold accent-coloured heading and extra space before the next group; retain native selection and keyboard behaviour. Tablets, caplets and capsules determine the count unit; oral liquids and injectable solutions determine ml. Label strength has the short subtitle The strength shown on the label. and the input placeholder Amount. Show its controls as one reading order: editable original label amount, compact mass-unit dropdown, then the bold accent-coloured original quantity such as per 5 ml or per 1 tablet. Convert retains that quantity and strength in the fields, with the amount remaining editable. Show a calculated per-one equivalent underneath only when the label quantity differs numerically from one. A one-unit label has no preview. Retain original label quantities after every conversion, including terminating ratios; derived values never replace them. Do not show the former leave-blank hint. Remove the separate For row. On narrow layouts or larger text, place the complete reference below the input pair rather than squeezing the controls. Do not offer incompatible dose units. Strength remains optional, with unknown kept unknown.

Convert opens a short guarded label-amount dialog. The person enters the exact original quantity and strength; confirmation calculates the per-one value. If a ratio cannot be represented exactly within normal input precision, retain the original rational relationship and mark its display as approximate. Never save a rounded display as the original strength. Clear removes the pending strength; Cancel changes nothing. Preserve draft, lock, dataset-generation and changed-field guards.

Powder-to-mix entries collect powder mass and final mixed volume rather than assuming an added-water amount equals the final volume. No volume or dose is inferred from a product name. Oral powder remains weight-based; it does not invent a liquid concentration. Medicine creation stores identity and reference strength first. Actual dose and stock remain separate confirmations, and the existing Details editor uses the same strength controls later.

## Dates and repeats

The owner requested Workout's canonical date/time/calendar styling, full range support and repeat interaction on 23 October 2026. Use the shared `lib/ui/pickers` implementation for every date/time entry. This replaces typed date/ISO examples as the normal interaction; storage formats and explicit timezone meaning remain unchanged. Keep original partial/unknown dates available for supporting history and use periods.

Preserve the original calendar geometry: 440px date frame with 28px corners, 360px clock frame with 24px corners, vertically centred title/Today header with Today at the trailing edge, rounded selection summary, selected-day discs, continuous range bands and smooth five/six-row bounds. Day, month and year views page with the original directional transitions. Week selection highlights the whole week and retains the cross-month reveal. Range selection supports restart, active-endpoint and nearest-endpoint editing; callers choose deliberately. Start/end buttons open one range calendar. Each optional filter endpoint can still be cleared independently. Cancel, Back, Escape and outside dismissal change nothing. Selection callbacks remain previews; saving records always belongs to the parent workflow.

Use the same shadcn controls, Plus Jakarta Sans typography and semantic accent across these pickers. `VitalDialog` supplies dark glass and a fully opaque light surface; no Material dialog/button is substituted. The clock retains hour/minute dragging, 12/24-hour presentation and semantic adjustment actions. Date-only values stay civil dates; exact instants resolve in the explicit or observed zone, with missing/repeated clock times reviewed instead of guessed. Generation/lock changes dismiss pending pickers, and stale results cannot overwrite a changed field.

`CalendarEditor`/`CalendarRepeatDetails` own calendar repeat controls, with shared borderless bold weekday pills, bounded steppers, compact selectors and a factual existing preview. Support days, weeks, months and years, nominal dates, last day, ordinal weekday and last weekday; expose missing-date handling when needed. Weekly anchors use week selection; month/year anchors use the month picker. Repeating breaks use the same controls under More options. Keep Vital's existing exact elapsed-hour, untimed-count, mixed and time-window engines. Do not copy Workout occurrence-count assumptions into medication amounts or infer actual use from a planned occurrence.

Schedule shows Amount, then one grouped Schedule surface: Starting, Repeat, Times, Duration and When to take. Starting shares the other rows’ centred column alignment and body-text metrics. Instructions is a proper multiline input with a ghost Instructions placeholder, persistent semantic label and a quiet example. Timing stays visible above one Advanced expansion, with Show timing and Remind me again controls explained in plain English. Amount per time and Scheduled days off live together inside Advanced, with quiet descriptions and no nested disclosure. Its dropdown offers Anytime, At bedtime and the existing food instructions. Preserve an already-saved combined instruction as one explicit selection until the person changes it. The Times Add command is centred quiet text. Added/removed rows use the shared 380/260ms small spring settle, fade and continuous bounds, with no motion when reduced motion is enabled. Start/end controls use centred, human-readable dates as quiet text in their columns. Shared input fields and dropdown triggers use a clearly visible, soft neutral grey fill (`#E7E8EA`) in light mode; chips use a faint version of their own text colour, with visible focus and disabled states. Once is a one-day schedule; duration supports ongoing, days/weeks, a visible inclusive range, a recorded-amount target or depletion of one explicitly chosen tracked container. Recorded targets use actual current records; container endings use the stock ledger, never a forecast. New containers/restocks do not silently restart a completed course. Keep unusual timing and scheduled days off inside Advanced. Review must show actual next dates/times, exact amounts and meaningful end rules before Save.

The unit selector offers only compatible saved units and displays the existing strength equivalent live. Capture that strength with the plan; never infer concentration from a product name or edit the medicine from this form. Exact conversions that cannot fit the existing scheduling precision are refused with a recovery message rather than rounded silently.

## Shared motion

Use shared motion tokens and adapters behind the existing Vital/Stitch APIs. Feature widgets choose a semantic motion, not an arbitrary duration or local animation style. Keep shadcn as the control system.

| Motion | Duration | Geometry |
| --- | --- | --- |
| Press/release | 90 / 140 ms | Visual scale to 0.97; hit target stays fixed. Cancel pressed appearance when a drag takes over. |
| Choice/switch | 180 ms | Shared segment highlight moves continuously; retain native shadcn switch behaviour. |
| Root selection | 360 ms | Page movement and bottom-bar selection share one controller. |
| Detail arrival/return | 360 / 280 ms | Cupertino push with outgoing-page parallax, matching Workout's active push adapter. |
| Expand/collapse | 380 / 220 ms | Continuous bounds with a small reveal offset and fade; retain the content subtree. |
| Sheet open/close | 400 / 300 ms | Movement from the lower edge and coordinated scrim. |
| Dialog open/close | 260 / 200 ms | Fade with 0.96 to 1 scale around its centre. |
| Row changes | 220 ms | Add/remove and neighbouring layout settle together. |
| Calendar movement | 320 ms | Programmed period navigation; direct dragging uses physics. |
| Filter results | 180 ms | Stable controls, bounded result transition. |
| Progress | 480 ms | Animate to a confirmed factual value. |
| Theme | 180 ms | Palette changes without moving layout. |

Curves: arrival and geometry use `Curves.easeOutCubic`; departure uses `Curves.easeInCubic`. Full pages use Flutter's Cupertino transition geometry, including the secondary route animation, as Workout does. Scroll physics use bouncing with always-scrollable content and no glow; preserve inherited desktop input behaviour. Selection haptics accompany deliberate bottom-bar and segment changes. Avoid visible oscillation and decorative delays.

Execute commands immediately when invoked; animation does not delay dispatch. Retarget/reverse interrupted motion. Keep full-sized readable text stable during geometric transitions. Display exact new quantities directly, rather than counting through invented intermediate doses or balances. Animate surrounding progress only when its denominator/state is known. Show saved state after commit; Undo reverses the confirmed change.

Pinned shadcn controls retain their internal thumb/focus microinteractions where their API exposes no timing hook. Keep their native semantics and behaviour; do not copy a control merely to retime it. This exception is limited to internal control feedback. Vital owns the surrounding press, route, paging, sheet, dialog, disclosure, progress and theme motion.

Apply the app and system reduced-motion preferences centrally: direct state changes, stable geometry and usable status feedback. Keep scrolling user-controlled. Stop decorative animation while hidden/locked. Privacy coverage happens immediately. Keep blur strength fixed during transitions. Glass is enabled by owner direction; measured physical-device acceptance remains separate.

## Family surfaces

Adapt the sibling Workout tracker's shared surfaces to shadcn controls. Use a full-width, edge-attached bottom bar with an icon selection pill. The app bar is transparent at rest and reaches its glass treatment over the first 21 px of scroll, with Workout's eased progression. Ordinary cards use the inexpensive painted faux-glass fill, vignette and rims. Dark-mode bars, sheets, dialogs and menus use selected live glass, with a 28 px overlay radius and the existing opaque/high-contrast fallback. Light-mode chrome and overlays use solid theme surfaces. Light canvas remains pure white.

`VitalScaffold` measures its actual header/footer, including device insets. Content begins below the transparent header. Its scrolling viewport can paint behind both bars; trailing padding lets the final action scroll fully above the bottom bar. `VitalChromeInsets` carries geometry through branch Navigators. The transparent pinned obstruction in `VitalInsetScrollView` keeps focus/ensure-visible targets below the header. Feature code must reuse these adapters rather than add competing top/bottom SafeAreas.

Owner direction on 23 October supersedes the earlier runtime glass-off rule. Enabled appearance is not device validation: preserve explicit opaque surfaces, high-contrast fallbacks and the separate false physical-validation marker. Do not claim frame-time or accessibility acceptance from static analysis.

## Family controls

Use the shared control renderer for Vital and Stitch APIs. Adapt Workout's canonical overlay frame/action bar and form tokens to shadcn. Primary commands have a filled accent, secondary commands have softer emphasis, and dialog secondary actions use a quiet accent label. Warning/destructive commands use labelled tints. Retain explicit outlines where the owner requested them, native focus feedback, disabled/pending states and 48px targets. Shared icon commands and destination rows use the same interaction styling.

Short dialogs use a compact 440px maximum width, 18px bold title, 14px body and an 8px header/body gap. Keep footer actions 20px below the body; use an overflow action bar that stacks when needed while preserving action order and focus nodes. Do not apply an additional AlertDialog small-text/muted layer around an already composed frame. Small editor dialogs have no sheet handle. Keep current save, cancellation, draft, PopScope and pending-write guards.

Inputs use a soft fill and pill shape, with a 14px radius for multiline text. Preserve visible labels, native focus rings and high-contrast borders. Existing English copy, full medicine names, quantities remain authoritative. Use the Workout font families and shared type roles throughout the app. Geometry belongs in the shared component tokens, not individual screens.

Settings and its drilldowns use the shared Workout-family settings layout: centred accent label toolbar, open body, small section labels and flat rows. Use coloured icon badges for destinations and right-aligned shadcn switches. The hub is one continuous scrolling page with a centred profile header and navigation rows into subsections. Keep settings controls, data summaries and workflow details off the hub. Local data has its own subsection; report dates belong in Reports and confirmed backup status belongs in Backup. It has no tabs or horizontal pager. Existing group return URLs scroll to their section. Saved profile and subsection summaries contain real facts only. Subpages reuse the shared settings scope and EntryPage adapters, preserving guarded Back and form controllers. Data workflows retain review, destination and destructive-confirmation steps. Restore remains non-dismissible while replacing data. Preference choices disable during writes and allow a same-choice retry after failure.

## Screen creation recipe

1. State the task, canonical route, presentation from the table and primary action. Read its reference and the existing shared implementation.
2. Reuse shared containers, controls, motion and presenters. Use pure white light canvas, established dark colours, full names/units, device/keyboard safe areas and 48 px targets.
3. Define initial information and secondary disclosures. Specify each control's scope, pending/error result, dismissal, focus return, draft and lock behaviour.
4. Wire existing data/commands, preserving exact amounts, revision/generation checks and idempotency. Record missing capabilities in the roadmap.
5. Verify real interaction and route/state preservation, both themes, narrow/large text, keyboard, reduced motion and interruption. Capture the relevant states. Report physical-device evidence separately.
6. Update the screen matrix when adding a route or changing its presentation. Any required exception belongs here with its rationale and verification, not as an unexplained local animation.

## Implementation evidence

Before claiming a migration complete, demonstrate that controls use the intended overlay, paging changes real content, Back/dismissal preserves guarded work, exact values remain correct and motion can be interrupted/reduced. Run the relevant regressions and whole-project analysis; the release batch additionally runs the full suite, native boot and Android debug build. Profile frame timing on representative hardware before claiming measured performance. A GitHub debug prerelease is labelled a development build and does not close production signing, native delivery or device acceptance gates.

## Shared implementation

- `lib/ui/vital_motion.dart`: semantic timings, curves, fixed-hitbox press feedback, retained section/root paging and reduced-motion reveals.
- `lib/ui/vital_presenters.dart`: guarded task framing, adaptive live options, shadcn overflow menus and short decision routes.
- `VitalSurfaceFrame`, `VitalControlStyle`, `VitalProgress` and `VitalDisclosure` apply the standard to existing containers and controls.
- `vitalRoute` in `lib/app/vital_app.dart` selects the canonical route presentation. `EntryPage` reuses the current form engine inside task routes; modal presentation does not create another editor.
- `test/motion_standards_test.dart` exercises navigation retention, nested paging, scrim/Escape protection, pending writes, reduced motion and keyboard clearance.

## Current verification scope

On 23 October the owner explicitly deferred comprehensive tests while reviewing the live app. This family pass uses static analysis; an earlier focused inset diagnostic covered initial clearance and focus reveal. Full motion, capture, accessibility and device-performance regression runs remain deferred. Capture helpers depending on the old SingleChildScrollView or inset Scaffold rectangle need adaptation to the edge-to-edge viewport before that later run. This records the owner's current direction; it does not replace evidence requirements for future release claims.

## Family typography

The owner requires Workout typography throughout the app. Plus Jakarta Sans is the UI family; JetBrains Mono supplies numeric/code roles. Use the copied sibling font files at weights 400/500/600/700 through the shared VitalType, shadcn typography and settings roles. Both font families are bundled offline with their OFL notices and provenance in assets/fonts/WORKOUT.md. Original Stitch font assets remain reference evidence; existing exported documents retain their document font handling.

The owner explicitly withheld publication on 23 October pending visual approval. Keep this settings/typography pass local until that approval arrives.

## Light overlay correction

The owner requires solid Material-style surfaces in light mode. A sheet, dialog or menu must paint its full opaque theme surface so the dimmed underlying page cannot show through it. Modal background dimming remains enabled by explicit owner clarification; preserve the current focus, barrier, safe-exit and dismissal guards. Dark mode retains its glass treatment. The shared VitalGlassSurface selects this policy, and the appearance sample reports solid surfaces truthfully in light mode. No publication is authorised pending owner review.
