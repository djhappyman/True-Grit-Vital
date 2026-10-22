# Catalogue search

The lead recovered and completed the interrupted OpenCode implementation.
Typing waits for a 300 ms pause; keyboard Search/Enter searches immediately.
Clear resets the current query and results. A route-local session keeps the
verified catalogue release pinned; this does not admit a production corpus or
close G05.

Lead review fixed the in-flight disable/re-enable race, ignored caret-only
controller changes and fenced retained Select callbacks to their rendered
query generation. Older replies cannot replace current loading/error/results.
The shared `LabelledInput` now accepts optional focus, keyboard action and
submission callbacks, with unchanged defaults for existing callers. Catalogue
search uses it; the checkpoint's separate field clone was removed.

Verification: all 15 `test/catalogue_ui_test.dart` checks passed in the final
run. A capture-only run passed the narrow layout case in both themes; scoped
analysis, pinned formatting and patch checks passed. Coverage includes debounce,
explicit flush, clear, delayed and out-of-order replies, disposal, disable/re-enable,
retry, exact custom-entry text, pinned source provenance, stale Select and
complete product/source copy at 320 px with 2x text.

```sh
./tool/flutterw test --no-pub test/catalogue_ui_test.dart
./tool/flutterw test --no-pub --dart-define=VITAL_T04_CAPTURES=docs/design/reviews/2026-10-22-fifteen/T04 test/catalogue_ui_test.dart --plain-name '320 wide'
./tool/flutterw analyze --no-pub lib/features/catalogue/catalogue_picker.dart lib/features/recording/record_pages.dart test/catalogue_ui_test.dart
```

Real synthetic Flutter captures: [light](light-catalogue-320x2.png),
[dark](dark-catalogue-320x2.png). Both were inspected. These are host checks;
physical accessibility and full-corpus/device performance remain open.
Local logs retain the initial compile/fixture failures and final passing runs
under `.scratch/vital-implementation/fifteen-2026-10-22/verification/T04-*`.

Lead skills: installed `flutter-expert`, `codebase-memory`,
`verification-before-completion`, `better-writing`, `flutter-add-widget-test`,
`flutter-build-responsive-layout`, `ui-ux-pro-max` and its review references;
repository `vital-mobile-copy`, blueprint and rollout rules. Graph search,
bounded caller tracing and snippets established the shared input seam; cited
path coverage was checked and the changed source/tests read directly. No
complete-impact or catalogue licence claim is made.
