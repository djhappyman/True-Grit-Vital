# Edit saved amounts

The lead recovered the interrupted preset-edit checkpoint. Configure now offers
Edit for each saved amount. The shared dialog changes one exact amount/unit in
place, preserving order and the eight-entry limit. Duplicate amounts and
unsupported units are rejected. Editing a preset neither selects a dose amount
nor records a dose or changes a schedule.

Lead review bound the dialog to its original controller authority, dataset and
route, including a guarded write boundary. Lock/unlock or a retired dialog
cannot authorise a later write. Cancel/Escape leave the old preset intact before
commit. A failed write keeps the old value and the dialog can retry. Keyboard
Next moves between fields rather than unexpectedly saving the amount.

Verification: 13 final controller checks passed; three new dialog checks passed
alongside the four existing recording/preset UI checks. Scoped analysis,
formatting and patch checks are clean. Coverage includes exact decimal/unit
identity, order, restart/backup, limit/duplicate rejection, failure/retry, queued
context expiry, lock and dataset replacement, cancellation and unchanged entered
dose/record counts. The replacement fixture now reopens its preserved file to
verify it after the provider has correctly closed the old connection.

```sh
./tool/flutterw test --no-pub test/dose_presets_test.dart test/dose_presets_ui_test.dart
./tool/flutterw test --no-pub --dart-define=DOSE_PRESET_SNAPSHOTS=docs/design/reviews/2026-10-22-fifteen/T05 test/dose_presets_ui_test.dart --name 'editing a saved|captured before lock|dialog keeps'
./tool/flutterw analyze --no-pub lib/features/recording/dose_presets.dart lib/features/recording/dose_preset_panel.dart test/dose_presets_test.dart test/dose_presets_ui_test.dart
```

Final synthetic dialog captures, with bundled fonts:
[light](light-edit-390x1.png), [dark](dark-edit-390x1.png),
[light 320 px / 2x](light-edit-320x2.png),
[dark 320 px / 2x](dark-edit-320x2.png). Both themes were inspected. Physical
keyboard/screen-reader/device checks remain separate gates.

Lead skills: installed Flutter expert, graph, verification, widget/layout, copy
and UI review skills; repository copy skill, blueprint and rollout plan. Changed
paths received graph coverage checks, with stale/new ranges read directly.
The original packet supplies the bounded preset controller trace. Local logs
retain failed fixture checks and final passes under
`.scratch/vital-implementation/fifteen-2026-10-22/verification/T05-*`.
