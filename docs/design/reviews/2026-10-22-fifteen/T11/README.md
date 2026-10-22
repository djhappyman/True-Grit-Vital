# Seven-day plan totals

T11 was recovered by the lead from the interrupted DeepSeek checkpoint. The
canonical plan preview now summarises the displayed seven civil dates before
the existing 20-row display limit. A separate bounded expansion distinguishes
an incomplete week from a wider preview limit reached after that week.

- Counts include untimed daily entries, without assigning invented times.
- Quantities use exact scaled integers and remain separate by their actual unit.
- Paused/ended empty weeks, unplanned use and incomplete calculations have
  explicit states. These are planned quantities, not recorded use or adherence.
- Existing resolver policy, Preview/Save guards and boundary warnings remain.

The lead changed the new unplanned-use explanation to “No planned times or
fixed total.” and aligned the widget fixture's date with its UTC plan. The
capture boundary now includes the real theme canvas and viewport; transparent
content-only intermediate images were replaced by the four final captures.

Verification: 22 focused checks passed in `test/plan_preview_totals_test.dart`;
the final capture-only rerun passed one check. Scoped analysis found no issues,
and the pinned formatter and patch check passed. The checks exercise >20 rows,
exact fractions, different units, counts, finite/paused plans, unsupported
composition, unresolved zones, bounded calculations and 320 px / 2x layouts.

```sh
./tool/flutterw test --no-pub test/plan_preview_totals_test.dart
./tool/flutterw test --no-pub --dart-define=VITAL_T11_CAPTURES=docs/design/reviews/2026-10-22-fifteen/T11 test/plan_preview_totals_test.dart --plain-name 'captures both themes'
./tool/flutterw analyze --no-pub lib/features/plans/plan_form.dart lib/features/plans/plan_preview_totals.dart test/plan_preview_totals_test.dart
```

Final synthetic Flutter captures: [light](light-plan-preview-totals.png),
[dark](dark-plan-preview-totals.png),
[light 320 px / 2x](light-plan-preview-totals-narrow-double-text.png),
[dark 320 px / 2x](dark-plan-preview-totals-narrow-double-text.png).
The lead inspected both themes. Physical accessibility/performance and the
combined native boot remain separate gates.

Lead skills read from `/home/mike/.codex/skills/`: `flutter-expert`,
`codebase-memory`, `verification-before-completion`, `better-writing`,
`flutter-add-widget-test`, `flutter-build-responsive-layout`, `ui-ux-pro-max`
and its `references/pro-rules.md`; also the repository
`.agents/skills/vital-mobile-copy/SKILL.md`, interaction blueprint and plan.
Graph coverage was checked for all three source/test paths; the new helper and
test were read directly. The original planning packet supplies the bounded
preview/resolver trace; coverage is best effort rather than completeness proof.
