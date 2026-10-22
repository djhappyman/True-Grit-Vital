# Substance properties

D25–D27 extend the canonical Create, Details, Stock, Product and Record screens.
No additional destination or dependency was added.

- Guided Injectable/Oral/Other choices with conditional forms, optional explicit
  labelled strength and retained original catalogue wording.
- Individual mixed vials retain powder amount/unit, confirmed final volume,
  optional mixing liquid/amount/date and exact derived concentration.
- Optional hours/days half-life reference values, context and source; separate
  values for each ready-mixed product ingredient.
- Live equivalents beside the recording amount, tablet/capsule count conversion,
  frozen preparation/strength snapshots, guarded edits, draft recovery, schema 25
  migration and protected-backup restoration.

The five PNGs show light/dark guided creation and tablet recording, plus the
mixed-vial form at 320 px / 2× text / reduced motion. They use the real shared
components and synthetic records. The light canvas is white; controls retain
safe-area and keyboard handling. Captures were visually inspected.

## Verification

- 23 focused checks passed across feature domain/store, creation, recording,
  schema 23/24 upgrades and encrypted restore. The restore check verifies
  original preparation facts, half-life context/source and structured export.
- The 14-file regression sweep passed 123 checks and caught two duplicate
  equivalent presentations. The duplicates were removed; the subsequent
  21-check run passed all 11 stock UI cases plus feature arithmetic/storage.
- Final focused checks include unchanged selected choices, equal-strength
  count packs, frozen strength through corrections, invalid dates/amounts,
  recurring rational concentrations and unsupported volume/count conversion.
- Whole-project analysis passed without issues. Native Linux debug build and
  real Secret Service boot/persistence/navigation/export/backup passed; the
  runner verified removal of its temporary dataset and test secret. See
  [native evidence](native-boot.json).

Loaded skill paths and full command logs are retained locally under
`.scratch/vital-implementation/substance-properties-2026-10-22/`. They include
Flutter expert, architecture, exact logic/widget tests, responsive layout,
static analysis, verification, codebase memory, UI guidance and both copy skills.
Current Flutter/Riverpod/Drift documentation was checked against the pinned
stack. Generic skill examples did not replace shadcn/Riverpod or upgrade packages.

## Limits

Half-life is saved reference information, without inferred values or estimated
level curves. Dose entry keeps mg/ml/count; micrograms are supported for labelled
strength and powder amounts with exact internal conversion. Physical Android
accessibility/performance and production release gates remain open. No APK or
new release was requested for this feature run.
