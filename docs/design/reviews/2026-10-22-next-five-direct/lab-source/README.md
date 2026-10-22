# D17c lab trend source inspection

## Outcome

Each exact-value row in the disclosed Labs sparkline table now offers an
accessible `Open` action. The action pushes the existing canonical
`/supporting/:person/:id` detail route using the saved record's own person and
record ids. It passes the originating filtered Labs URL as `return`.

- No writes, draft changes or revision changes are made by source navigation.
- The collection stays mounted beneath the detail route, so Back restores the
  open table and the same filter state.
- Missing records reach the existing unavailable state. Lock uses the existing
  app lock coverage and hides saved content.
- The 24-point sample, segment/gap logic, table toggle, reduced-motion reveal
  and saved value precision are unchanged.

## Files

- `lib/features/supporting/supporting_sparkline.dart`
- `lib/features/supporting/supporting_source_link.dart`
- `lib/features/supporting/screen_labs_widgets.dart` (passes return context)
- `lib/l10n/app_en.arb` and generated localisations (`directLabSourceAction`)
- `test/screen_labs_sparkline_source_test.dart`

## Verification

- `./tool/flutterw test --no-pub test/screen_labs_sparkline_source_test.dart`
  -> 6 passed
- `./tool/flutterw test --no-pub test/lab_features_ui_test.dart test/screen_labs_ui_test.dart`
  -> 16 passed
- `./tool/flutterw analyze`
  -> No issues found

## Remaining limits

- No physical-device screen-reader or large-text evidence.
- Per-record deletion is not exposed by the domain; the unavailable state was
  verified through the same canonical route with a missing saved id.

## Integrated review

The lead used URI path segments to preserve record identity and added a nested
filtered-return test. The final capture run passed eight source checks,
including 320 px/2x text in both themes. Reviewed Flutter captures:
[light](light-lab-sources.png), [dark](dark-lab-sources.png).
Final whole-project analysis found no issues.
