# Lab latest values

D17 remaining gap. The latest section now reads the newest dated current result
for every marker across the complete filtered collection, not only three pages
of records. Kind, linked item, linked event and collection-date filters apply.
Unknown dates and voided records stay excluded, and a newest missing result is
shown as missing instead of falling back to an older value.

The arbitrary 75-record window and 60-marker cap are gone. A bounded store query
returns one marker page and the exact total marker count. `Load` requests the
next 24-marker page using an offset, and Previous returns to the prior page.
Each request remains the same size; it does not reread a growing prefix or
load the full collection payload into Dart. Store calls reject page sizes above
100. Empty pages after live edits retain a Previous recovery action. Each marker
keeps the saved record header, selected result, original unit, range, flag,
provenance and date precision.

Comparisons still require the exact metric, unit, laboratory, method and
specimen identity. The per-marker sparkline is a recent sample of up to 24 dated
results and the section states that coverage. A value with a different identity,
a censored or qualified value, or a missing value breaks the line. Saved-context
names remain bounded to 24 distinct links; when that bound is reached the
section says some linked records are not named.

## Verification

- 8 focused pure projection checks in `test/screen_labs_latest_test.dart`.
- 6 datasetwide store/provider checks in
  `test/screen_labs_latest_dataset_test.dart`, covering a marker older than 75
  records, more than 60 markers, kind/item/event/date filters, corrections,
  voids, newest missing values, comparison identity, sparkline breaks, live
  refresh, app lock and a restored dataset generation.
- 12 focused collection checks in `test/screen_labs_ui_test.dart`, including a
  30-marker collection that moves from `Markers 1 to 24 of 30` to
  `Markers 25 to 30 of 30` through Load, then returns through Previous.
- A broader supporting regression run passed 57 checks.
- Project analysis passed with no issues.

Captures use synthetic data in the actual `/supporting` route with device
padding and the existing shell:

- [Light](light-labs-latest.png)
- [Dark](dark-labs-latest.png)
- [Dark, 320 px and double text](dark-labs-latest-narrow-double-text.png)

## Lead review

The initial integrated latest-value suite passed 24 checks. Lead review then
made marker requests fixed-size pages, added exact range labels and constrained
store page sizes, and hid retained values while replacement providers load.
The 80-marker fixture visits every page without overlaps or dropped markers.
Comparison coverage now explicitly discloses its 48-result sample alongside the
24-point trend sample. The full panel detail uses the separate complete prior
query; the dashboard does not claim a complete comparison history.

A new regression reproduced a false prior value when two comparable results
belonged to the same earlier panel. The bounded partial-record projection now
reunites that panel's selected results before the existing comparison algorithm
handles ambiguity. A boundary record is omitted from comparison when its result
group may have been cut by the sample. Both normal duplicate results and a
sample-boundary duplicate are tested. The updated data/projection/widget run
passed 26 checks, with clean project analysis. Captures were regenerated after
the paging and coverage-copy changes.

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
