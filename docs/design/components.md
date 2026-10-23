# Building Vital screens

For every existing or new screen, follow the [interaction blueprint](interaction-blueprint.md) before choosing navigation, sheets, dialogs, popovers or motion. Its [rollout plan](interaction-implementation-plan.md) records current migration status; the component catalogue below describes the existing shared entry points.

Use `lib/ui/vital_ui.dart` for existing forms and secondary pages. Dashboard and Substances use the closer reference components in `lib/ui/stitch_ui.dart`. It composes shadcn controls; feature code retains its existing Riverpod state, commands and navigation.

The owner selected the strongest components from the [Stitch references](stitch/2026-10-20/README.md) as a visual vocabulary. Reuse that vocabulary across the implemented features. The light canvas is pure white; dark mode uses the reference's green-black canvas and mint accents. The navigation dock stays fixed at the bottom. Device safe areas apply to every screen.

## Form baseline

New and revised sheet/page forms follow the [approved form standard](interaction-blueprint.md#form-standard), using the saved [medicine reference](reviews/2026-10-23-form-standard/README.md). Reuse `VitalFormRow`, `VitalFormActions`, `VitalField` and `LabelledInput` rather than copying the reference's widget tree. Subtitles explain useful choices; ghost text is selective, with persistent accessible names. Pages use Cancel/primary button columns; sheets stack primary/Cancel. The medicine creation flow is the first adopter. Untouched forms retain their rollout status.

## Components

| Component | Use |
|---|---|
| `VitalPage` | Secondary screen with safe areas, optional title/header actions and a scrolling body. |
| `VitalScrollBody` | Scrollable content inside an existing shell. Owns gutters and readable maximum width. |
| `VitalPageHeader` | Page title, optional context/icon and wrapping actions. |
| `VitalPanel` | Related form fields, settings or review information. `inset` provides a secondary surface. |
| `VitalSurface` | Low-level card/sheet surface when a feature needs its own composition. |
| `VitalSection` | Section heading and related cards, with an optional action. |
| `VitalRecordHeader` | Complete record name, optional supporting details and a form/context icon. |
| `VitalField` | Visible label and helper around an existing input. |
| `VitalAnimatedRows` | Stable keyed insert/remove motion with a small spring settle, coordinated bounds and read-only exit snapshots. Reduced motion skips the animation. |
| `VitalActions` | Contextual actions that wrap safely with narrow widths or larger text. |
| `VitalFormRow` | Two equal field columns with a 12px gutter, stacking when width/text scaling needs it. |
| `VitalFormActions` | Text-only form footer: stacked primary/Cancel in sheets, equal Cancel/primary columns on full pages, with measured large-text fallback. |
| `VitalButton` | Primary, secondary or destructive shadcn command, including pending state. |
| `VitalIconButton` | Labelled 48px icon command with shared press, hover and focus behaviour. Used by filter and overflow triggers. |
| `VitalNavigationRow` | One destination with an optional icon and explanation, a soft action-row surface and a trailing chevron. Use its quiet variant for flat medicine choices inside a sheet. Settings rows delegate here. |
| `VitalPickerField` | Canonical day/week/month/time/exact-instant/partial-date entry with unchanged controller storage formats and stale-result guards. |
| `VitalDateRangeField` | One range calendar for two endpoints; supports inclusive/exclusive upper bounds and independently clearable open-ended filters. |
| `showVitalDatePicker`, `showVitalDateRangePicker`, `showVitalDateTimePicker`, `showVitalTimePicker` | Workout's full calendar/clock mechanics on Vital's shared dark-glass/opaque-light dialog host. Prefer fields in forms; use these entry points for standalone navigation or specialised metadata. |
| `CalendarEditor`, `CalendarRepeatDetails` | Calendar recurrence mapped to Vital's existing domain engine; use shared weekday pills, steppers and transitions rather than feature-specific repeat widgets. |
| `VitalWeekdayPicker`, `VitalRepeatStepper`, `VitalRepeatTransition` | Shared repeat control styling, haptics and reduced-motion-aware conditional fields. |
| `VitalSegments` | Short mutually exclusive choices with accessible selection and keyboard behaviour. |
| `VitalBadge` | A factual, labelled status. Tone supplements the text. |
| `VitalCompactRow` | A wrapping identity/summary row with optional keyboard-accessible activation and a visible focus ring. Trailing content stays non-interactive when the whole row is an action. |
| `VitalMetric` | A complete labelled value with optional detail; an unknown value stays explicitly unknown. |
| `VitalProgress` | A factual proportion with visible values and denominator; `noTotal` and `unknown` show explanatory text without a progress bar. |
| `VitalNotice` | Information or a problem kept together with its recovery action. |
| `StitchSectionCard` | Framed section with a shared icon, heading, optional subtitle/status and content; trailing content stacks at large text sizes. |
| `StitchEmptySlot` | Borderless inset empty slot with a quiet centred plus and a descriptive accessible action. |
| `VitalEmptyState` | Clear orientation and an optional next action for an empty collection. |
| `VitalIconTile` | Consistent decorative icon container beside a meaningful label. |
| `VitalDialog`, `VitalDialogActions` | Compact glass decision/editor frame with a bounded body and footer actions that stack when a row cannot fit. |
| `VitalType`, `VitalLayout` | Semantic typography and shared spacing/geometry. |
| `VitalSettingsPage`, `VitalSettingsToolbar`, `VitalSettingsBody` | Workout-family centred glass toolbar and open settings/drilldown layout. Existing forms pass their guarded Back callback. |
| `VitalSettingsSection`, `VitalSettingsLabel`, `VitalSettingsRow` | Small section labels and flat destinations with 44px colour badges, 16px titles and complete supporting text. |
| `VitalSettingsCard`, `VitalSettingsType` | Modest 16px faux-glass cards for factual summaries and the shared settings text roles. |

`EntryPage`, `Heading` and `PageContent` remain compatibility adapters for existing features. Durable forms can override `buildEntryPage(children)` to compose their page chrome while keeping draft, lock, generation, safe-exit and deferred post-save navigation in `DurableFormState.wrap`; do not copy those guards into a screen. New features should use the shared UI entry point directly. Settings retain their established semantic navigation/toggle rows within `VitalPanel` groups.

`VitalComponentThemes` gives native shadcn text fields a soft neutral grey fill (`#E7E8EA`) that visibly separates fields from white surfaces in light mode and the existing Workout-family fill in dark mode, pill radius and 18/16px horizontal/vertical padding. Resting borders are quiet; native focus rings remain visible, and high contrast retains an explicit input border. `LabelledInput` uses a 14px radius for multiline text. Screens inherit these defaults rather than copying local field decoration.

`VitalControlStyle` is the renderer for both Vital and Stitch buttons. Primary commands use a filled accent and a bold 14px label. Ordinary secondary commands use a soft neutral fill; dialog secondary commands use a quiet accent label. Warning and destructive commands use labelled amber/red tints. Explicit outlined commands retain their outline. Disabled/pending, hover, focus and press states remain distinct without adding Material controls.

`lib/ui/vital_dialog.dart` adapts Workout's canonical overlay frame and action-bar composition. Short dialogs default to 440px maximum width, an 18px bold title, 14px body text, 24px content padding and a 20px footer gap. Large text reduces content padding to 16px. The existing dialog presenter retains route and dismissal ownership; shadcn's transparent `ModalContainer` provides the modal surface without another AlertDialog content-style layer. Existing action callbacks, order and focus nodes are passed through unchanged. Small route editors use the same width/title/action emphasis and omit sheet handles.

`SubstanceSummary(item: ..., detailed: ...)` in `lib/features/substances/substance_summary.dart` supplies bounded live schedule, next-dose and per-container stock information. It renders content inside the caller's container, preserves units and partial states, and uses the existing resolver rather than inventing dates or dose equivalents. `SubstanceContainerSummary` reuses its per-container presentation inside overview sections without duplicating whole schedule or stock sections.

## Settings family

Settings follows Workout's settings surface and drilldown components. Keep the centred accent label toolbar at a minimum 64px, expanding for large text. Use 16px hub gutters and 20px drilldown gutters, 12px initial spacing and trailing breathing room inside the measured viewport. Section labels sit outside containers. Destinations and switches use flat rows; storage/profile/backup facts may use a modest faux-glass card. Do not wrap the entire page in a panel or repeat its title below the toolbar.

The hub is one continuous list without tabs, with navigation rows only beneath its profile header. Local data opens `/settings/storage`; report dates and backup status stay inside Reports and Backup. General/Privacy/Data return links scroll to section anchors. Its centred 96px profile header reads the saved local name; the toolbar Edit command opens the existing editor. Appearance, Profile, Reminders, Privacy, Diagnostics, Help and licence pages use the same presentation through `VitalSettingsScope`; the scope has no storage authority. Existing EntryPage/durable-form adapters retain their controllers and pass safe-exit callbacks to the toolbar. Reports, Export, Backup and Restore keep their established review and confirmation stages with matching headers/body surfaces. Restore's toolbar remains disabled while replacement is active.

All shared segmented pills centre their labels and use bold text for selected, unselected and disabled choices. Width measurements use the same bold type so horizontal overflow remains scrollable. Colour mode and time format use shared segments, with real disabled semantics during a write. A failed preference save permits selecting the same choice again to retry. Appearance's existing samples sit under a disclosure. Preserve system appearance, opaque surfaces, reduced motion, app lock and all permission/capability explanations. The new styling adds no settings, network access or example profile facts.

## Stitch screens

`lib/ui/vital_foundation.dart` is the single source for `VitalLayout`, `VitalType`, `VitalPalette`, `VitalColors`, `VitalSurfaceFrame` and `VitalControlStyle`. Existing `VitalSurface`/`VitalButton` and the Stitch compatibility widgets delegate to those renderers. Badges, icon tiles and scroll bodies also share their implementation. A theme card-colour override reaches both surface APIs; geometry and typography changes belong in this foundation rather than a feature file.

`StitchType` aliases `VitalType`, so it inherits the owner’s Workout-family typography correction. Plus Jakarta Sans supplies UI text and JetBrains Mono numeric/code roles. Their exact sibling assets, hashes and licences are recorded in `assets/fonts/WORKOUT.md`. The older StitchSans assets and `assets/fonts/STITCH.md` remain source-reference evidence. `StitchColors` reads the same shadcn semantic palette as existing widgets. Light secondary text is slightly darker than the export to retain readable contrast on inset controls. `StitchSurface`, `StitchButton`, `StitchBadge`, `StitchIcon` and `StitchScrollBody` supply the reference geometry with native shadcn interactions and device insets. Targets remain at least 48 px; text can wrap.

The dashboard composition comes from `dashboard-timeline-velocity-dark-mode--42445af1`; Substances comes from `substances-dark-mode--1ecd8e65`, with saved light variants informing the white theme. The owner’s 22 October [dashboard reference](reviews/2026-10-22-dashboard-schedule/owner-reference.png) now takes precedence for Today composition; the original Stitch exports remain authoritative for other screens. Preserve complete names and quantities and keep real commands connected. The owner's subsequent direction permits explicit placeholders for missing features: they must identify unavailable behaviour and must never save example data.

## A feature screen

```dart
VitalPage(
  title: text.stock,
  leading: VitalButton.secondary(
    onPressed: onBack,
    child: Text(text.back),
  ),
  children: [
    VitalPanel(
      title: container.label,
      children: [
        VitalField(
          label: text.amountLabel,
          child: TextField(controller: amountController),
        ),
        VitalActions(children: [
          VitalButton(onPressed: onSave, child: Text(text.save)),
          VitalButton.secondary(onPressed: onBack, child: Text(text.cancel)),
        ]),
      ],
    ),
  ],
)
```

For an existing ungrouped form, `VitalPage(panelled: true, ...)` supplies one panel around its body. For collections or several sections, compose explicit panels/cards. Keep one scroll owner and preserve controller, focus and draft identity across rebuilds.

## Theme and layout

- Read semantic colours from shadcn `Theme.of(context).colorScheme`; update shared tokens in `lib/app/vital_theme.dart`.
- Use the bundled Plus Jakarta Sans UI family and JetBrains Mono numeric/code family. `VitalType` supplies title, section, record, body, metadata, label and quantity roles. Quantities use tabular figures.
- Use 16px page gutters, a 640px maximum content region, 24px card corners, 28px sheet corners and at least 48px interactive targets. Containers grow for content and text scaling.
- Place related information in one panel. Use the inset surface for a meaningful subgroup, without turning every line into another card.
- Use `VitalScaffold` and `VitalInsetScrollView` for measured header/footer and device insets. Content starts below the transparent app bar, scrolls behind the glass, and has enough trailing padding to clear the bottom bar. Keep keyboard avoidance and one scroll owner. Decoration reaches screen edges; interactive content respects safe areas.
- `VitalFauxGlassSurface` paints the Workout-family card treatment without per-card backdrop blur. `VitalGlassSurface` supplies dark-mode glass and solid light-mode theme surfaces for selected bars and overlays while retaining shadcn controls. The bottom bar is full-width and edge-attached. Glass is enabled by owner direction, with opaque/high-contrast fallbacks; physical-device performance validation remains open.

## Before a UI pull request

Reference the relevant Stitch screen and explain which shared components it informed. Include light/dark screenshots, with a narrow-screen and large-text check for changed layouts. Preserve full names, amounts and units. Use existing localised strings and the repository's copy rules.

The screenshots contain generated example data and some invented capabilities. Connect implemented controls to the real feature; clearly label unavailable previews. Never display example clinical values or invented stock forecasts as saved data. Review changes against the functional specification as well as the visual references.

Run `./tool/flutterw test --no-pub test/visual_framework_test.dart test/design_system_test.dart` for the shared framework checks. To capture synthetic screen previews, add `--dart-define=VITAL_UI_SNAPSHOTS=output/ui-review` to that command. Native device accessibility and performance require separate verification.

For a focused capture, add `--dart-define=VITAL_UI_ROUTES=substances` (or comma-separated route keys from the visual test). Omitting it checks every listed route; unknown keys fail instead of silently skipping the check.

Today uses the owner’s framed calendar and daypart Schedule cards. Only the date strip pages; the surrounding surface and month controls stay stationary; no selected-date footer or divider is shown. Borderless Empty/taken-count chips sit on the period title row. Empty periods offer a centred plus with a visible suggested time in the existing schedule editor. One outlined Plan button sits below the timeline. Unplanned medication uses a plain-English subtitle, compact name/amount rows and an outlined Add command beneath the card matching Plan. Observations remains a compact Coming soon preview. The greeting uses the shared detail-title type role; card borders and optional outlined shadcn commands are rendered by the shared foundation. Taken and Undo retain their durable commands, while source/interval/stale-data/clock guards retain their existing review UI. Substances keeps its live bounded summaries and unified overview.

Regenerate this closer reference review with `./tool/flutterw test --no-pub test/stitch_reference_screens_test.dart --dart-define=VITAL_STITCH_CAPTURES=output/stitch-review`. The fixture uses synthetic records only and captures loaded light/dark viewport and full-content screens. Physical-device accessibility and performance remain separate gates.

The 23 October owner direction defers comprehensive tests for the family glass/motion pass. The commands above remain the later verification workflow; static analysis alone does not validate motion, screenshots or device performance.

Light-mode overlay surfaces are fully opaque, using the semantic popover/card colours. The existing background dimming can remain: it sits behind the solid sheet/dialog, with no backdrop sampling or translucency in the light surface. Dark glass and opaque/high-contrast preferences keep their existing policy.

Quick medicine entry reuses `MedicineFormFields` and `MedicineStrengthFields`. Its full-width grouped native select uses two/three-word subtitles and sets the unit from the chosen form. The reference row is fixed at one tablet/caplet/capsule or one ml. Strength uses mg/micrograms. Convert accepts original label amounts; exact ratios survive without turning a rounded preview into saved strength. Powder-to-mix entries use original powder amount and confirmed final volume. These values describe strength, with stock and actual dose recording remaining explicit workflows.

Inputs and dropdown triggers share the visible soft neutral grey light-mode fill (`#E7E8EA`), with a neutral hover treatment. Chips use a faint version of their text/semantic tone as their fill, preserving selected and warning states. Dark-mode fills retain their existing treatment.

Label strength reads left to right as the original amount, a compact mass-unit selector and the bold accent-coloured original label quantity. Show the calculated per-one equivalent below only when the original quantity is not one. Original conversion amounts remain intact and editable even when the per-one decimal is exact. The unit selector can use a short selected label while retaining the full menu and accessibility label. The reference moves below the input pair when width or text scaling needs it. Grouped `VitalSelect` menus use spaced, bold accent-coloured group headings and a small gap before option subtitles, retaining native shadcn selection and focus behaviour.

`MedicineCategoryField` reuses saved personal item types for quick medicine grouping, with ten starter choices, brief subtitles, compact selected labels and complete accessible/menu labels. Its create dialog stages a new name in the existing medicine draft; the guarded item command persists the category and medicine together. `MedicineFormFields` places it beside the form selector in two equal columns, stacking for narrow or large-text layouts. `VitalSelect.footerBuilder` supports a native-popup trailing command; close the popup with its own handle before opening a dialog.
