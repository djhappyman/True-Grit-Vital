# Vital interaction blueprint

Version 4. Owner approved the standard on 21 October 2026 and the Today simplification and framed Schedule direction on 22 October 2026. This is the definitive presentation and motion standard for existing and future screens. Implementation status is tracked separately in the [rollout plan](interaction-implementation-plan.md); approval of this standard does not mean every screen has migrated.

Use this blueprint with the [shared components](components.md), [design references](README.md), single-user specification and mobile copy contract. The original Stitch exports remain visual evidence; the owner's later History calendar and interaction decisions take precedence. Changes to this blueprint require an explicit explanation of the changed rule and updated examples/tests. Keep one current rule rather than adding contradictory exceptions.

## Choose the presentation

| User intent | Presentation | Contract |
| --- | --- | --- |
| Visit a main destination | Persistent root page | Today, Substances, Events and History share a PageView and fixed dock. Preserve each page's state. |
| Browse peer sections | Tabs and PageView | Use for substance Overview/Schedule/Stock/History and Settings General/Privacy/Data. One canonical screen, with distinct content per tab. Keep the tab strip on one row; scroll it when large text cannot fit. |
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

Single-dose recording initially shows substance identity, amount/presets, actual time, relevant source and the exact stock/strength consequence, followed by Save. Existing optional fields appear under More. Multi-source recording uses an expanded sheet with complete source identities and quantities. A source chooser can be an internal sheet step with Back; avoid stacking task sheets.

Reuse the current durable form controller/command path. Every dismissal path, including scrim, drag, Escape and system Back, enters the same safe-exit policy. Keep/discard decisions preserve the draft on cancellation. A pending or uncertain write is resolved before another save or unsafe dismissal. Restore focus to the invoking control or a surviving neighbour.

Preserve record/correction deep links. A directly opened sheet receives a valid underlying destination. Confirm success only after durable commit; communicate saved/failure once and retain existing review/Undo paths. Privacy lock immediately covers the sheet and its underlying records.

## Today composition

The profile control sits on the left of the app bar. Today uses a local-time greeting and the saved profile name. Keep the shared chrome, fixed dock and device safe areas. At large text sizes, put the greeting on its own full-width row and keep dock labels in one horizontally scrollable row, preserving space for the page and full-size text.

Use one timeline for planned doses. Group by expected Morning, Afternoon and Evening; show Night or No set time only when needed. With planned entries, omit empty groups. With none, show the three daytime headings and quiet inset empty states. Label this area Schedule. Place a borderless status chip on the right of each daypart title: Empty, an exact taken/planned count, or Partial when the read is incomplete. Skipped doses do not count as taken; never invent totals. Each empty daypart uses the shared framed section component with a meaningful icon and time range. Its borderless empty inset contains only a quiet centred plus with a descriptive accessible planning label. Keep one full-width outlined Plan button beneath the timeline, including empty days. The contextual plus seeds a visible suggested time in the existing editor: Morning 08:00, Afternoon 14:00, Evening 20:00. The person reviews quantities and time before Preview/Save; no plan or dose is automatically committed. Preserve exact quantities, expected times, Taken, Skip, Snooze, Extra, Edit, Undo, incomplete calculation warnings and source/strength review through the existing row component. Do not duplicate a next-dose hero, progress row, weekly summary or separate Recorded/Manage section.

Unplanned medication means actual use without an active planned-dose action. Its information dialog explains this in plain English. Add opens `/unplanned`, a guarded task sheet containing whole-collection search, existing medicine selection or minimal creation. Choosing a medicine uses the existing dose editor, with the selected date visible and editable. Plan uses the same chooser and then the existing schedule editor, seeded with the selected date. Minimal creation saves a medicine identity first; the dose is a separate confirmed save. Cancelling the dose retains the medicine. Its name, form and other details remain editable in the existing Details editor; saved doses keep their original snapshots and units. Quick-create drafts retain their original day and task context.

Keep unplanned entries scoped to the displayed day, with exact actual quantities/units and correction access. Existing drafts, pending attachment jobs and consequential stock warnings remain reachable. Observations remains the explicitly requested compact Coming soon card, with no entry action. The unplanned section uses one enclosing shared surface, a plain-English subtitle and compact correction rows showing only full medicine name and exact amount/unit. Its Add command sits beneath the card and matches the full-width outlined Plan button. The [latest refinements](reviews/2026-10-22-dashboard-refined/README.md) supersede the footer, dashed empty inset and primary Add treatment in the approved [reference](reviews/2026-10-22-dashboard-schedule/owner-reference.png). Use the same semantic typography, framed surfaces and controls as the rest of the app.

## Shared motion

Use shared motion tokens and adapters behind the existing Vital/Stitch APIs. Feature widgets choose a semantic motion, not an arbitrary duration or local animation style. Keep shadcn as the control system.

| Motion | Duration | Geometry |
| --- | --- | --- |
| Press/release | 100 / 180 ms | Visual scale to 0.985; hit target stays fixed. |
| Choice/switch | 220 ms | Selected surface/thumb moves to its new position. |
| Root selection | 280 ms | Page movement and dock selection remain coordinated. |
| Detail arrival/return | 380 / 300 ms | Short directional movement, up to 18 px, with fade. |
| Expand/collapse | 420 / 300 ms | Continuous bounds/corners; dependent content follows. |
| Sheet open/close | 440 / 300 ms | Movement from the invoking edge and coordinated scrim. |
| Dialog open/close | 320 / 220 ms | Fade with 0.96 to 1 scale around its centre. |
| Row changes | 300–360 ms | Add/remove and neighbouring layout settle together. |
| Calendar movement | 340 ms | Programmed period navigation; direct dragging uses physics. |
| Filter results | 220 ms | Stable controls, bounded result transition. |
| Progress | 480 ms | Animate to a confirmed factual value. |
| Theme | 280 ms | Palette changes without moving layout. |

Curves: arrival `Cubic(0.22, 1, 0.36, 1)`, geometry `Cubic(0.65, 0, 0.35, 1)`, departure `Cubic(0.4, 0, 1, 1)`. Gesture-driven snaps are gently damped and respect release velocity. Avoid visible oscillation and large travel. Optional choreography uses at most three groups, approximately 35 ms apart, finishing within 500 ms.

Execute commands immediately when invoked; animation does not delay dispatch. Retarget/reverse interrupted motion. Keep full-sized readable text stable during geometric transitions. Display exact new quantities directly, rather than counting through invented intermediate doses or balances. Animate surrounding progress only when its denominator/state is known. Show saved state after commit; Undo reverses the confirmed change.

Pinned shadcn controls retain their internal thumb/focus microinteractions where their API exposes no timing hook. Keep their native semantics and behaviour; do not copy a control merely to retime it. This exception is limited to internal control feedback. Vital owns the surrounding press, route, paging, sheet, dialog, disclosure, progress and theme motion.

Apply the app and system reduced-motion preferences centrally: direct state changes, stable geometry and usable status feedback. Keep scrolling user-controlled. Stop decorative animation while hidden/locked. Privacy coverage happens immediately. Keep blur strength fixed during transitions; glass still requires its existing measured-device gate.

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
