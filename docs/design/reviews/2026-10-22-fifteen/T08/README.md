# Stock movement filters

All, Recorded, Restock, Waste, Measured and Corrections filter the ledger before
50-row paging. The existing history sheet, exact quantities, saved identities
and source Open actions remain in use. Reset restores All; changing kind starts
at the newest page. Empty later pages step back. Filter state is scoped to the
container and resets with lock/dataset changes.

Lead checks: `test/data/stock_movement_filter_test.dart`,
`test/stock_movement_filter_ui_test.dart`, `test/stock_movement_source_test.dart`.
Cases include more than 50 mixed movements, exact kind mapping, paging, source
returns, keyboard, dismissal, loading/failure and dataset shrink. Existing source
assertions were scoped for the additional Recorded control; the Restock editor
fixture now targets its command rather than the identically named filter.

The four PNGs use synthetic records, bundled fonts and the real app: both themes
at 390 px and 320 px/2x text. These are host captures, not physical-device proof.
