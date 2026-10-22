# D13g/D14 explicit inventory sort

Adds an explicit `Name` / `Expiry` choice to the canonical Stock inventory
filter disclosure. `Name` keeps the existing order. `Expiry` orders saved full
pack dates ascending and puts containers without a saved date last.

## Behaviour

- The disclosure keeps its existing state filters, overlap help and expiry
  cutoff. A `Sort` section now shows the current choice and one short rule:
  saved dates from the earliest, containers without a date last.
- Expiry ordering is applied by the store to the whole bounded filtered
  snapshot, after search, item scope, balance/plan filter and cutoff, and only
  then does the page slice 50 rows. Counts, completeness, search, item scope,
  filter and cutoff semantics are unchanged.
- Known dates are ordered ascending. Ties use the saved item name and then the
  container id, so repeated reads and live updates stay deterministic.
- Unknown dates sort last. Ordering uses only the saved civil date, so it works
  without an observed local day or time zone and never invents a relative
  "soon" state.
- Changing the sort resets paging to the first 50 rows. A visible
  `Sorted by expiry` chip exposes the non-default sort and resets it to `Name`.
  `Clear` resets search, filter, cutoff and sort together.
- The bounded 2,000-container warning is unchanged and remains visible below
  the chip. The sort help describes a rule, not a whole-collection earliest
  result; omitted rows are never presented as the earliest inventory.
- No stock, plan or pack metadata is written. The choice is an additive,
  default-`Name` API so existing record-typed inventory queries keep their
  existing shape and results.

## Files

- `lib/domain/stock/stored_stock.dart`
- `lib/data/stock_store.dart`
- `lib/features/stock/stock_providers.dart`
- `lib/features/stock/stock_pages.dart`
- `lib/l10n/app_en.arb` and generated locales
- `test/data/stock_inventory_sort_test.dart`
- `test/stock_inventory_sort_ui_test.dart`

`lib/features/stock/stock_widgets.dart` is untouched.

## Verification

- `./tool/flutterw analyze --no-pub --fatal-infos` — no issues.
- `./tool/flutterw test --no-pub test/data/stock_inventory_sort_test.dart
  test/stock_inventory_sort_ui_test.dart` — 13 passed: exact 60-row order,
  ties and nulls, filtered/paged composition, zone-independent ordering, live
  metadata edits, store and provider lock, bounded incompleteness, UI paging,
  sort reset, chip reset, Clear, search and balance composition, loading, error,
  keyboard activation, Back, reduced motion, 320/390/430 px at double text and
  both-theme captures.
- `./tool/flutterw test --no-pub test/data/stock_inventory_store_test.dart
  test/data/stock_expiry_cutoff_test.dart test/screen_stock_inventory_test.dart
  test/stock_expiry_cutoff_ui_test.dart test/stock_ui_test.dart` — 48 passed.
- `dart format --output=none --set-exit-if-changed` on the changed Dart files —
  clean. The repository-wide format check still lists unrelated pre-existing
  test files from the parent revision; those were not reformatted.

## Captures

Real Flutter fixtures rendered through `VitalApp` with synthetic records:

- `light-sort.png`, `dark-sort.png` — selected `Expiry`, active chip and the
  earliest known pack first at 390 px.
- `light-sort-sheet.png`, `dark-sort-sheet.png` — the sort choice and rule in
  the filter disclosure.
- `light-sort-narrow.png`, `dark-sort-narrow.png` — 320 px at double text with
  the active sort chip, wrapped names and no overflow.

Regenerate with:

```sh
./tool/flutterw test --no-pub test/stock_inventory_sort_ui_test.dart \
  --plain-name 'capture sort' \
  --dart-define=VITAL_STOCK_SORT_CAPTURES="$PWD/docs/design/reviews/2026-10-22-third-five/d13g"
```

## Limits

- Physical-device layout, screen-reader output and measured performance remain
  unverified.
- The sort choice lives with the page's other filter state; it is not persisted
  across app launches. Persistence was not requested.
- The lead reproduced the reported narrow-sheet Escape failure, then fixed
  keyboard focus and Escape dismissal in the shared VitalLocalOptions component.
  System Back and Escape preserve the chosen sort. The four collection destinations
  now verify initial focus, Escape dismissal and return to the invoking control.
