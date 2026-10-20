# Release readiness

Fail-closed checks for tickets 27 (private pilot) and 28 (public release).
These checks never convert missing physical, publisher or signing evidence into
a pass.

```sh
# Static preflight only (fast).
python3 tool/release/readiness.py

# T10 focused checks: preflight, regression tests and the host boot fixture.
./tool/release/run_checks.sh

# Full suite plus preflight; the lead uses this for the combined check.
./tool/verify checks
```

Machine-readable output is written under `build/`, which is not committed.

## What passes mean

| Check | A pass proves | A pass does not prove |
|---|---|---|
| `toolchain` | `.flutter-version`, pubspec constraints and `tool/flutterw` agree on Flutter 3.47.7 / Dart 3.13.5. | The SDK is installed or the app builds. |
| `dependencies` | A lockfile exists with the pinned constraints and only the reviewed `pdfium_dart` override. | Every package is suitable for release. |
| `licences` | Every resolved hosted package has a version/archive/notice audit, and native notices are present. The bundled reader includes exact package, font and native texts. | Human licence/permission review or store compliance. |
| `android-release-config` | No debug-key release signing, no cleartext/network permission, backup and transfer exclusions, no unexpected exported components. | A release build or device behaviour. |
| `release-metadata` | Module detection and public capability metadata agree; integrations update the inventory in the same change. | Accurate store listing or privacy policy. |
| `obligations` | All 78 stories, 20 screens, 8 sheets, 13 schedule families, C01–C12 and G01–G08 appear exactly once with an owner and existing evidence paths. | The evidence actually passes. |
| `boot-fixture` | A host fixture exists that boots the real shell on synthetic storage. | Native launch, Android or accessibility. |
| `host-widget-boot` (boot matrix) | The shell boots and primary navigation renders on this host. | Linux native, emulator, physical device, performance. |

## Maintaining the inventory

Update `tool/release/obligations.json` when a work package changes an owner,
route or gate state. A gate becomes `passed` only with evidence paths and a
named reviewer. A story becomes `host-tested` only with existing test paths.

Update `tool/release/capabilities.json` in the same integration commit that lands
reports, exports, backup/restore or privacy/help. Until then the preflight fails
if a module appears while the docs still call it unavailable, or if the docs stop
saying it is unavailable while no module exists.

The lead must update both files when integrating T02–T09, then run
`./tool/verify checks` and `python3 tool/release/boot_matrix.py --run-host --devices`.
Physical Android, publisher/territory/privacy wording, store submission and
owner-supplied signing remain owner/lead gates.

Regenerate the bundled licence reader after an admitted dependency/notice change with `python3 tool/release/build_notices.py`; `tool/verify` checks it against the exact cached package LICENSE files after locked dependency resolution.
