# Stock detail changes

Pack history compares lot, expiry and exact capacity against the immediately
preceding saved revision for the same container. Added, cleared, changed,
unchanged and unknown values stay distinct. Missing revisions never supply an
inferred old value; migrated snapshots are not authored edits. Full saved values
remain under the shared Saved details disclosure.

Twenty rows plus one predecessor/next-page lookahead keep boundary comparisons
exact. Lead review fixed an unreachable final revision in the checkpoint's
paging rule and added empty-page fallback. No schema or metadata writes changed.

Checks: `test/stock_metadata_diff_test.dart` and
`test/screen_stock_metadata_test.dart`, including fractions, gaps, migration,
21/45-row boundaries, live updates, failed reads, lock, saved drafts and both
themes at 320/390/430 px with 2x text. PNGs in `captures/` are synthetic Flutter
fixtures using bundled fonts. Native accessibility remains a separate gate.
