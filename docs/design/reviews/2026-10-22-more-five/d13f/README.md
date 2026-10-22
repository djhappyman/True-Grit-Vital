# D13f inventory expiry cutoff

Adds one explicit, user-chosen inclusive expiry cutoff to the canonical Stock
inventory. It extends the existing Expired and Expires today choices without
introducing a clinical or shelf-life window.

## Behaviour

- The filter disclosure has a persistent `Expiry cutoff` label, ISO
  `YYYY-MM-DD` entry, `Apply` command and inline validation. An invalid date
  leaves the previously applied cutoff and results unchanged.
- A saved pack expiry on the chosen day is included; later dates and containers
  without a saved expiry date are excluded.
- The cutoff is compared as a civil date, so it works without an observed
  device day or time zone. Existing Expired/Expires today counts still require
  the observed day and stay unavailable without it.
- Search and item scope are applied by the store before the cutoff, and the
  cutoff is applied to the whole bounded 2,000-container read before the page
  slices 50 rows. Applying or clearing the cutoff resets paging.
- The full cutoff appears in a visible chip, the disclosure and the specific
  filtered-empty state. The chip clears only the cutoff; `Clear` resets the
  search, stock filter and cutoff together.
- Pack metadata and stock are read only. No clinical threshold or automatic
  "soon" window is inferred.

## Files

- `lib/domain/stock/stored_stock.dart`
- `lib/data/stock_store.dart`
- `lib/features/stock/stock_providers.dart`
- `lib/features/stock/stock_pages.dart`
- `lib/l10n/app_en.arb` and generated locales
- `test/data/stock_expiry_cutoff_test.dart`
- `test/stock_expiry_cutoff_ui_test.dart`

## Verification

- `./tool/flutterw analyze` — no issues.
- `./tool/flutterw test --no-pub test/data/stock_expiry_cutoff_test.dart` — 5
  passed: inclusive cutoff, zone-independent cutoff, search/item composition
  past 50 rows, balance-filter composition, provider wiring and locked hide.
- `./tool/flutterw test --no-pub test/stock_expiry_cutoff_ui_test.dart` — 8
  passed: exact/inclusive filter, invalid and cleared states, search plus 55
  rows and paging, filtered-empty state, loading, error, 320 px double text in
  both themes and captures.
- Existing `test/data/stock_inventory_store_test.dart` and
  `test/screen_stock_inventory_test.dart` — 23 passed.

## Captures

Real Flutter fixtures rendered through `VitalApp` with synthetic records:

- `light-cutoff.png`, `light-cutoff-full.png`, `light-cutoff-narrow.png`
- `dark-cutoff.png`, `dark-cutoff-full.png`, `dark-cutoff-narrow.png`

Regenerate with:

```sh
./tool/flutterw test --no-pub test/stock_expiry_cutoff_ui_test.dart \
  --plain-name 'capture cutoff' \
  --dart-define=VITAL_EXPIRY_CUTOFF_CAPTURES="$PWD/docs/design/reviews/2026-10-22-more-five/d13f"
```

## Limitations

The functional narrow-width test applies the cutoff at 390 px, then resizes the
page to 320 px at double text to verify the chip, filtered rows and layout. The
shared `VitalLocalOptions` adaptive sheet does not enter its open position in
the current widget harness when an animation controller is supplied; this
pre-existing shared behaviour also affects the existing filters at widths below
360 px or text scale above 1.5. The real sheet layout and keyboard behaviour at
320 px therefore remain for lead/host verification, and no shared presenter
file was changed in this slice.
