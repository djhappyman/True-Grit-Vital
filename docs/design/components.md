# Building Vital screens

Use `lib/ui/vital_ui.dart` for existing forms and secondary pages. Dashboard and Substances use the closer reference components in `lib/ui/stitch_ui.dart`. It composes shadcn controls; feature code retains its existing Riverpod state, commands and navigation.

The owner selected the strongest components from the [Stitch references](stitch/2026-10-20/README.md) as a visual vocabulary. Reuse that vocabulary across the implemented features. The light canvas is pure white; dark mode uses the reference's green-black canvas and mint accents. The navigation dock stays fixed at the bottom. Device safe areas apply to every screen.

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
| `VitalActions` | Actions that wrap safely with narrow widths or larger text. |
| `VitalButton` | Primary, secondary or destructive shadcn command, including pending state. |
| `VitalSegments` | Short mutually exclusive choices with accessible selection and keyboard behaviour. |
| `VitalBadge` | A factual, labelled status. Tone supplements the text. |
| `VitalCompactRow` | A wrapping identity/summary row with optional keyboard-accessible activation and a visible focus ring. Trailing content stays non-interactive when the whole row is an action. |
| `VitalMetric` | A complete labelled value with optional detail; an unknown value stays explicitly unknown. |
| `VitalProgress` | A factual proportion with visible values and denominator; `noTotal` and `unknown` show explanatory text without a progress bar. |
| `VitalNotice` | Information or a problem kept together with its recovery action. |
| `VitalEmptyState` | Clear orientation and an optional next action for an empty collection. |
| `VitalIconTile` | Consistent decorative icon container beside a meaningful label. |
| `VitalDialog` | Bounded dialog with scrolling content and reachable actions. |
| `VitalType`, `VitalLayout` | Semantic typography and shared spacing/geometry. |

`EntryPage`, `Heading` and `PageContent` remain compatibility adapters for existing features. New features should use the shared UI entry point directly. Settings retain their established semantic navigation/toggle rows within `VitalPanel` groups.

`SubstanceSummary(item: ..., detailed: ...)` in `lib/features/substances/substance_summary.dart` supplies bounded live schedule, next-dose and per-container stock information. It renders content inside the caller's container, preserves units and partial states, and uses the existing resolver rather than inventing dates or dose equivalents. `SubstanceContainerSummary` reuses its per-container presentation inside overview sections without duplicating whole schedule or stock sections.

## Stitch screens

`lib/ui/vital_foundation.dart` is the single source for `VitalLayout`, `VitalType`, `VitalPalette`, `VitalColors`, `VitalSurfaceFrame` and `VitalControlStyle`. Existing `VitalSurface`/`VitalButton` and the Stitch compatibility widgets delegate to those renderers. Badges, icon tiles and scroll bodies also share their implementation. A theme card-colour override reaches both surface APIs; geometry and typography changes belong in this foundation rather than a feature file.

`StitchType` aliases `VitalType` and transcribes the export's 28/20/17/14/13/12/11 px hierarchy and line heights. `StitchSans` bundles the original archive's Noto Sans weights 400/500/600/700; provenance and licence are in `assets/fonts/STITCH.md`. `StitchColors` reads the same shadcn semantic palette as existing widgets. Light secondary text is slightly darker than the export to retain readable contrast on inset controls. `StitchSurface`, `StitchButton`, `StitchBadge`, `StitchIcon` and `StitchScrollBody` supply the reference geometry with native shadcn interactions and device insets. Targets remain at least 48 px; text can wrap.

The dashboard composition comes from `dashboard-timeline-velocity-dark-mode--42445af1`; Substances comes from `substances-dark-mode--1ecd8e65`, with saved light variants informing the white theme. These are the only design sources. Preserve complete names and quantities and keep real commands connected. The owner's subsequent direction permits explicit placeholders for missing features: they must identify unavailable behaviour and must never save example data.

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
- Use the bundled Noto Sans family. `VitalType` supplies title, section, record, body, metadata, label and quantity roles. Quantities use tabular figures.
- Use 16px page gutters, a 640px maximum content region, 24px card corners, 32px sheet corners and at least 48px interactive targets. Containers grow for content and text scaling.
- Place related information in one panel. Use the inset surface for a meaningful subgroup, without turning every line into another card.
- Every route is protected by the app-level safe area. `VitalPage` also works safely on its own. Keep custom scroll views clear of device insets and the keyboard; retain the shell's fixed dock outside the scrolling body.
- Forms, records and charts remain opaque. `VitalChrome` integrates the existing glass preference/capability gate for selected chrome, with a styled opaque fallback. The device-performance gate remains open; a dependency does not establish measured glass readiness.

## Before a UI pull request

Reference the relevant Stitch screen and explain which shared components it informed. Include light/dark screenshots, with a narrow-screen and large-text check for changed layouts. Preserve full names, amounts and units. Use existing localised strings and the repository's copy rules.

The screenshots contain generated example data and some invented capabilities. Connect implemented controls to the real feature; clearly label unavailable previews. Never display example clinical values or invented stock forecasts as saved data. Review changes against the functional specification as well as the visual references.

Run `./tool/flutterw test --no-pub test/visual_framework_test.dart test/design_system_test.dart` for the shared framework checks. To capture synthetic screen previews, add `--dart-define=VITAL_UI_SNAPSHOTS=output/ui-review` to that command. Native device accessibility and performance require separate verification.

For a focused capture, add `--dart-define=VITAL_UI_ROUTES=substances` (or comma-separated route keys from the visual test). Omitting it checks every listed route; unknown keys fail instead of silently skipping the check.

Today uses a measured daily completion ring, the next actionable dose card and compact time groups. Taken and Undo call the existing durable commands. The hero activity icon opens Details, including stock source, Extra and editing; stock/interval/stale-data/clock guards retain their complete review UI. Manage reveals full stock notices and schedule controls. Substances uses live bounded summaries; tapping a card opens the existing unified overview, including Record, schedule, stock and history.

Regenerate this closer reference review with `./tool/flutterw test --no-pub test/stitch_reference_screens_test.dart --dart-define=VITAL_STITCH_CAPTURES=output/stitch-review`. The fixture uses synthetic records only and captures loaded light/dark viewport and full-content screens. Physical-device accessibility and performance remain separate gates.
