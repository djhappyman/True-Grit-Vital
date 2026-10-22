# Stock expiry filters

Task branch: `t3/stock-expiry-filters` at baseline `0dab613`.

The stock inventory now has collection-wide `Expired` and `Expires today`
filters and counts. They use the existing `StockExpiryState` comparison against
the observed local civil day at the supplied `asOf`; a missing or invalid zone
leaves both counts null and reports the filter as unavailable instead of using
UTC or showing zero. Search and item scope run in the same bounded store query
before the UI page slice, and the existing balance, paused and unresolved
meanings are unchanged. Item cards and their actions are untouched.

Verification:

- `./tool/flutterw test --no-pub test/data/stock_inventory_store_test.dart`:
  11 tests passed, including 2001-container bound, UTC vs UTC+14 day, metadata
  watch refresh and missing/invalid zone.
- `./tool/flutterw test --no-pub test/screen_stock_inventory_test.dart`:
  12 tests passed, including live metadata edit, search/filter composition,
  ambiguous no-zone state and 320 px double text in both themes.
- `./tool/flutterw test --no-pub test/data/stock_metadata_store_test.dart
  test/screen_stock_metadata_test.dart test/stock_ui_test.dart
  test/stock_surface_route_switch_test.dart`: 21 tests passed.
- `./tool/flutterw analyze`: no issues found.
- `git diff --check`: clean.

Skills read: `flutter-expert`, `codebase-memory`, `dart-add-unit-test`,
`dart-run-static-analysis`, `verification-before-completion`,
`flutter-add-widget-test`, `flutter-build-responsive-layout`,
`interaction-design`, `ui-ux-pro-max`, `better-writing` and the repository
`vital-mobile-copy` skill from the main checkout because this worktree lacks
gitignored `.agents/` and specification docs. No skill-file read failure
occurred.

Graph: Tier 2 `codebase-memory-mcp` project
`home-mike-Development-true_grit_vital`, generation `2026-10-22T18:29:58Z`.
`check_index_coverage` reported no recorded issue for the edited source and
test paths. Methods in part-file extensions were confirmed by direct reads.

Remaining limits: physical-device checks, screen-reader announcement of the
new chip state and a measured large-collection profile are not covered here.
