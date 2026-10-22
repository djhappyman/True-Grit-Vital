# T10 saved site history

Extends the optional site editor with one collapsed, read-only history of
saved doses that still have a site label. It lists the current saved label, the
saved item name and the saved dose actual time, keeps corrected and voided
state explicit, and shows the first saved audit label when a site edit replaced
it. It never suggests a next injection site.

Each row keeps the canonical source identity: a combined component opens its
combined action, a separate dose opens its record. The route is the shared
History source with a URI-encoded return to the mounted site form, so Back
returns to the same guarded draft. Opening history writes nothing.

## Evidence

`./tool/flutterw test --no-pub test/site_history_store_test.dart`: 6 pass.

- Current labels ordered by saved actual time, then record id.
- Distinct label choices (`siteHistory`) stay separate and undated.
- A site edit leaves the dose revision alone; a correction or void advances it.
- Cleared sites leave the labelled history but keep the choice audit.
- Combined components keep the combined action as their source.
- Stale expected revision rejects without changing saved history.
- Paging is bounded (max 500) and stable across ties.

`./tool/flutterw test --no-pub test/site_history_ui_test.dart`: 8 pass in the lead's final run.

- Collapsed by default; expanding and opening history leaves no draft.
- An unfinished site draft survives the source round trip and platform Back
  still offers the keep/discard decision.
- Corrected and voided rows stay visible with their current state.
- Twenty rows per page with Next/Previous over 25 synthetic doses.
- Locked content is hidden and the draft returns after unlock.
- Empty state when no saved dose has a site label.
- Live saved-label changes refresh the list without replacing an unfinished
  site draft. A page emptied by a site clear returns to the previous page.
- Layouts at 390, 430 and 320 with 2x text, in light and dark, with no
  overflow exception.

Captures in this folder are real Flutter widget renders from the synthetic
fixture (no saved app data): `390x1x-*`, `430x1x-*`, `320x2x-*` in light and
dark.

The OpenCode run committed its implementation before its connection failed.
The lead recovered that commit, replaced the cached history provider with a
bounded watched query and added both live-change regressions. The combined
verification also passed six store and eight existing combined-flow checks;
scoped analysis and the pinned formatter are clean. An initial paging-test wait
matched a separate label choice; the corrected wait targets the exact source
row and the final eight-case UI run passes. Local command logs are retained in
`.scratch/vital-implementation/fifteen-2026-10-22/verification/T10-*.log`.

## Limits

Physical-device accessibility, screen-reader reading order and measured
performance are not claimed here. The lead runs the combined build and native
boot for the batch.
