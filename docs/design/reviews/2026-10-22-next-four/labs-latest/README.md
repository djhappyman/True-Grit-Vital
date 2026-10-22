# Lab latest values

D17 remaining gap. The latest section now reads the newest dated current result
for every marker across the complete filtered collection, not only three pages
of records. Kind, linked item, linked event and collection-date filters apply.
Unknown dates and voided records stay excluded, and a newest missing result is
shown as missing instead of falling back to an older value.

The arbitrary 75-record window and 60-marker cap are gone. A bounded store query
returns one marker page and the exact total marker count. `Load` requests the
next page by increasing the bounded marker request; it does not load the full
collection payload or scan every result into Dart. Each marker keeps the saved
record header, selected result, original unit, range, flag, provenance and date
precision.

Comparisons still require the exact metric, unit, laboratory, method and
specimen identity. The per-marker sparkline is a recent sample of up to 24 dated
results and the section states that coverage. A value with a different identity,
a censored or qualified value, or a missing value breaks the line. Saved-context
names remain bounded to 24 distinct links; when that bound is reached the
section says some linked records are not named.

## Verification

- 8 focused pure projection checks in `test/screen_labs_latest_test.dart`.
- 4 datasetwide store/provider checks in
  `test/screen_labs_latest_dataset_test.dart`, covering a marker older than 75
  records, more than 60 markers, kind/item/event/date filters, corrections,
  voids, newest missing values, comparison identity, sparkline breaks, live
  refresh, app lock and a restored dataset generation.
- 12 focused collection checks in `test/screen_labs_ui_test.dart`, including a
  30-marker page that moves from `24 of 30 markers` to all 30 through `Load`.
- A broader supporting regression run passed 57 checks.
- Project analysis passed with no issues.

Captures use synthetic data in the actual `/supporting` route with device
padding and the existing shell:

- [Light](light-labs-latest.png)
- [Dark](dark-labs-latest.png)
- [Dark, 320 px and double text](dark-labs-latest-narrow-double-text.png)

## Limits

The latest marker page request, sparkline sample and comparison candidate sample
are bounded. The sparkline is explicitly a recent sample, never full history.
No clinical, optimal, risk, causal or adherence classification is introduced.
Physical screen-reader, performance and native-device acceptance remain open.

## Skills and evidence

Read the installed Flutter expert skill and its Riverpod and widget references,
codebase-memory, architecture, unit test, widget test, responsive layout,
ui-ux-pro-max, static analysis, better-writing and
verification-before-completion skills, plus the repository mobile copy skill.
The graph project `home-mike-Development-true_grit_vital` was checked at
generation `2026-10-22T09:38:14Z` with Tier 2 best-effort coverage on every
evidence path. The new store and dataset test files were not yet indexed, so
their source was read directly and is treated as the authoritative evidence.
