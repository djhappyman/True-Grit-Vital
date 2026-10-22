# Delete confirmation

The existing Delete records dialog captures the original dataset, owner revision,
lock session and route. Cancel starts focused; dismissal returns focus. A lock
cycle, dataset/revision replacement, route departure or duplicate activation
cannot turn an old confirmation into a new deletion.

The service carries authority through generated-copy cleanup and into the
transaction. The writer checks again before commit; a failed guard rolls back
records, drafts, reminder intent and the operation receipt. Exact retry retains
the existing command replay semantics. Deletion scope is unchanged.

Checks: `test/app/privacy_delete_authority_test.dart`,
`test/settings/privacy_ui_test.dart`, `test/settings/privacy_replacement_test.dart`
and `test/privacy_delete_capture_test.dart`. They exercise replacement with the
same IDs/revision, stale revisions, lock/unlock, failed cleanup, commit rollback,
retry, cancellation, safe focus and route departure. Four synthetic real-font
PNGs show the dialog in both themes at 390 px and 320 px/2x text. No physical
storage-erasure or external-copy deletion claim is made.
