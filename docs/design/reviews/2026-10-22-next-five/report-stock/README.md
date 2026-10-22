# Report stock details

D13b adds one optional, default-off `Stock details` choice to the canonical
Reports selection. When selected, R01, R02 and R03 add the saved container
facts linked to each recorded dose by its own `actualUse` stock movement:

- the complete container label and its measurement unit;
- the saved lot, when recorded;
- the civil expiry date, when recorded;
- the exact pack capacity in the container's unit. Terminating values stay
  decimal (`0.125`); other values stay exact fractions (`1/3`), never rounded.

Capture reads the same `stock_movement` to `stock_container` link used by
structured exports. It never derives a container from a balance, strength or a
neighbouring movement, and a dose recorded without a chosen container stays
without one. Corrections keep the source because the movement remains linked to
the record identity. The facts are described in every template as saved
container metadata at report capture, not historical dose-time facts, product
authenticity or proof of ingestion.

The selection JSON keeps `stock` absent when off, so an older stored selection
decodes false and keeps its identity. Turning the option on adds `stock: true`
to the hashed selection identity; the controller then discards any reviewed
artifact, so preview and export cannot reuse a document built under the other
choice. The option is blocked while capture, rendering or handoff is busy.
Private notes, attachments, supporting records, dates, template, event and item
filters are unchanged.

The report text alternatives include the same four facts per listed dose, plus
one explicit disclosure. A selected section with no chosen container says so;
a mixed list states that details appear only for doses linked to a chosen
container. R01 keeps the existing `pw.TextOverflow.span` on long supporting
metadata and long private notes.

## Skills read

- `/home/mike/.codex/skills/flutter-expert/SKILL.md`
- `/home/mike/.codex/skills/flutter-expert/references/riverpod-state.md`
- `/home/mike/.codex/skills/flutter-expert/references/widget-patterns.md`
- `/home/mike/.codex/skills/codebase-memory/SKILL.md`
- `/home/mike/.codex/skills/flutter-apply-architecture-best-practices/SKILL.md`
- `/home/mike/.codex/skills/dart-add-unit-test/SKILL.md`
- `/home/mike/.codex/skills/flutter-add-widget-test/SKILL.md`
- `/home/mike/.codex/skills/flutter-build-responsive-layout/SKILL.md`
- `/home/mike/.codex/skills/ui-ux-pro-max/SKILL.md`
- `/home/mike/.codex/skills/dart-run-static-analysis/SKILL.md`
- `/home/mike/.codex/skills/better-writing/SKILL.md`
- `/home/mike/.codex/skills/verification-before-completion/SKILL.md`
- `/home/mike/Development/true_grit_vital/.agents/skills/vital-mobile-copy/SKILL.md`

The pinned Riverpod `Notifier`/shadcn stack overrides dated generic examples.
The report text itself uses the existing authored-string pipeline rather than a
second localisation system; the new selection copy uses the owned
`featureReportStock` ARB prefix and regenerated localisations.

## Verification

- Graph project `home-mike-Development-true_grit_vital`, generation
  `2026-10-22T08:41:37Z`, Tier 2. `check_index_coverage` reported
  `no_recorded_issue` for the selected report source paths and
  `not_tracked` for `app_en.arb`; the flagged source was read directly. The
  caveat remains best-effort, not proof of completeness.
- `./tool/flutterw test test/reports test/report_stock_capture_test.dart`
  passed 77 focused checks. This covers selection defaults and legacy JSON,
  identity invalidation, date and item filters, consistent capture, chosen
  source, correction retention, missing metadata, stockless disclosure,
  text/PDF parity for R01/R02/R03, exact fractions, controller busy/lock
  invalidation and the Reports toggle.
- `./tool/flutterw analyze` passed with no issues after the final import cleanup.
- `git diff --check` passed.

The capture test exercised 390 px and 320 px with 2x text and reduced motion,
plus a 430 px 2x layout assertion, with no exception or overflow. Synthetic
captures use the real Reports route and device-safe insets:

- [Light](light-report-stock.png)
- [Dark](dark-report-stock.png)
- [Light, 320 px and double text](light-report-stock-narrow.png)
- [Dark, 320 px and double text](dark-report-stock-narrow.png)

Physical-device screen readers, measured performance, real product authenticity
and historical container state at dose time remain outside this evidence.
