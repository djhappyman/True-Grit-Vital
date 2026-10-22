# Forecast inspection

D14d extends the existing stock forecast with a collapsed Details disclosure.
It shows the exact opening balance, planned use and remaining amount or final
day shortfall, with inclusive dates and the resolved plan zone. Non-terminating
quantities stay exact fractions. Nothing writes stock or recommends a dose.

The result carries totals only after every amount in its disclosed range has
resolved. Unsupported schedules, unknown balances, missing clocks/zones and
bounded expansion failures disclose no partial totals. Finite-plan and horizon
results can show fully calculated totals without inventing a run-out date.

Seven domain checks cover exact conversions, whole final days, intervals,
finite plans, plan-zone dates, an empty horizon and unsupported states. Five
widget checks cover fractions, both themes at 320 px/2x, collapse, lock hiding,
read-only balances and real Flutter captures. Forty-eight stock/domain/motion
regression checks passed. These counts overlap existing checks and are not a
whole-suite claim. Final combined verification is recorded by the batch review.

Captures: [light](light-forecast-details.png), [dark](dark-forecast-details.png).
Synthetic fixtures use the canonical inventory and shared controls. Physical
screen-reader, Android and measured-performance evidence remains open.

Loaded skill paths: `/home/mike/.codex/skills/flutter-expert/SKILL.md` and its
widget reference; codebase-memory; Dart unit testing/static analysis; Flutter
widget testing/responsive layout; interaction-design; ui-ux-pro-max;
better-writing; verification-before-completion; and the repository
`.agents/skills/vital-mobile-copy/SKILL.md`. The focused UX catalogue search
returned no verified disclosure match; the existing interaction blueprint and
shared VitalDisclosure define the implementation instead. Flutter accessibility
and widget-testing primary documentation were checked against the pinned stack.

Graph Tier 2, project `home-mike-Development-true_grit_vital`. Existing stock,
provider, shared disclosure and fixture paths had no recorded coverage issues.
The forecast function's body extends beyond the indexed signature and was read
directly; new projection/widget-test files were also read directly.
