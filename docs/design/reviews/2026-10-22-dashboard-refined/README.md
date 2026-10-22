# Dashboard refinements

22 October 2026. This is the current Today composition, following the owner's
final refinements to the [approved reference](../2026-10-22-dashboard-schedule/owner-reference.png).
The PNGs are real Flutter captures with synthetic records in both themes.

- Calendar dates page inside a stationary frame; the selected-date footer and divider are removed.
- Borderless Empty/taken-count chips sit beside daypart titles. Empty insets contain a quiet centred plus.
- One outlined Plan button follows the timeline. Unplanned medication has a plain-English subtitle, compact name/amount rows and a matching Add button beneath it.
- Existing recording, correction, Undo, medicine creation/editing, drafts and schedule preview/save remain connected.
- Large text gives the greeting a full-width row and scrolls dock labels horizontally, keeping page content usable. Observations remains a Coming soon preview.

The current [blueprint](../../interaction-blueprint.md) and
[component guide](../../components.md) define the shared implementation.
Phone-height captures show the scrolling layout; full-height captures expose
all content in a taller viewport. No demonstration records are shipped in the app.

Verification: the full suite finished with 2,230 passing tests, one skipped
and one search-test synchronization failure. The test now waits for the live
filtered result rather than matching its own input text; all seven tests in
that file then passed. The 27 focused dashboard, paging, dismissal, draft,
large-text and schedule checks passed. Whole-project analysis is clean.
The full suite was not repeated after this test-only correction.
Native Linux boot, real keyring use, encrypted persistence, navigation, reports,
export and backup passed; [the runner result](native-boot.json) confirms cleanup
of its isolated dataset and key. Android debug compilation and signature
verification passed (version 0.1.0, build 2).
Physical Android performance, TalkBack and lifecycle acceptance remain open.
