# R04 barcode dependency and data admission

Checked 23 October 2026 for local pack scanning. This record covers the exact
versions resolved by `pubspec.lock` after `flutter pub get`; it is not broad
approval of later versions, other barcode libraries or a medicines catalogue.

## Direct runtime additions

| Package | Resolved | Licence | Primary evidence | Purpose |
|---|---|---|---|---|
| `flutter_zxing` | 3.1.0 | MIT | https://pub.dev/packages/flutter_zxing/versions/3.1.0/license; `docs/implementation/licenses/flutter_zxing-3.1.0-LICENSE` | Dart/camera-FFI bridge to the bundled ZXing C++ decoder. |
| `camera` | 0.12.1 | BSD-3-Clause | https://pub.dev/packages/camera/versions/0.12.1/license; `docs/implementation/licenses/camera-0.12.1-LICENSE` | Camera lifecycle, permission and preview-frame stream for the scanner. |
| `camera_platform_interface` | 2.15.0 | BSD-3-Clause | `docs/implementation/licenses/camera_platform_interface-2.15.0-LICENSE` | Development-only fixture construction of a luminance camera frame. |

`flutter_zxing` is not an ML Kit wrapper. Its Android and Linux builds compile
the vendored `zxing-cpp` C++ source; there is no Google barcode SDK, downloaded
model, OCR engine or remote recogniser in this path. The gallery button in its
reader widget is disabled; no image is picked, copied, retained or uploaded by
Vital. `image_picker` remains a transitive platform package of the plugin but is
never invoked.

## Bundled native engines

| Component | Bundled version | Licence | Evidence |
|---|---|---|---|
| ZXing C++ decoder/writer | 3.1.1 | Apache-2.0 | https://github.com/zxing-cpp/zxing-cpp/tree/v3.1.1/LICENSE |
| `librscpp` | bundled with ZXing C++ 3.1.1 | Apache-2.0 | SPDX headers in `core/src/librscpp/*.h` |
| `libzueci` | bundled with ZXing C++ 3.1.1 | BSD-3-Clause | SPDX headers and README in `core/src/libzueci/` |
| `libzint` writer backend | 2.16.0 | BSD-3-Clause (library backend) | https://github.com/zint/zint/tree/2.16.0/LICENSE and backend headers |

The exact notices are retained in
`docs/implementation/licenses/barcode-native-NOTICES.txt` and are included in
the shipped `assets/legal/notices.txt` licence surface, not only in this
Markdown record. `tool/release/build_notices.py` rebuilt that asset and its
check mode verifies it.

## New transitive packages

| Package | Resolved | Licence |
|---|---|---|
| `camera_android_camerax` | 0.7.6 | BSD-3-Clause |
| `camera_avfoundation` | 0.10.3+1 | BSD-3-Clause |
| `camera_platform_interface` | 2.15.0 | BSD-3-Clause |
| `camera_web` | 0.3.5+6 | BSD-3-Clause |
| `file_selector_linux` | 0.9.4+1 | BSD-3-Clause |
| `file_selector_macos` | 0.9.5+2 | BSD-3-Clause |
| `file_selector_platform_interface` | 2.7.0 | BSD-3-Clause |
| `file_selector_windows` | 0.9.3+6 | BSD-3-Clause |
| `flutter_plugin_android_lifecycle` | 2.0.35 | BSD-3-Clause |
| `image_picker` | 1.2.4 | BSD-3-Clause; bundled `aFileChooser` Apache-2.0 |
| `image_picker_android` | 0.8.13+25 | BSD-3-Clause; bundled `aFileChooser` Apache-2.0 |
| `image_picker_for_web` | 3.1.1 | BSD-3-Clause |
| `image_picker_ios` | 0.8.13+13 | BSD-3-Clause; bundled `aFileChooser` Apache-2.0 |
| `image_picker_linux` | 0.2.2 | BSD-3-Clause |
| `image_picker_macos` | 0.2.2+1 | BSD-3-Clause |
| `image_picker_platform_interface` | 2.11.2 | BSD-3-Clause |
| `image_picker_windows` | 0.2.2 | BSD-3-Clause |
| `mime` | 2.1.0 | BSD-3-Clause |
| `stream_transform` | 2.1.2 | BSD-3-Clause |

Exact LICENSE bytes for every package above are retained under
`docs/implementation/licenses/<package>-<version>-LICENSE`, hashed in
`tool/release/package_licences.json`. No package has a proprietary,
source-available, noncommercial or model-download restriction.

## Platform, privacy and permissions

- Android adds `android.permission.CAMERA`; camera and autofocus features are
  declared optional so the app remains installable without a camera.
- Manifest merge rules explicitly remove `RECORD_AUDIO`,
  `READ_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE`, which the camera plugin
  declares for video/file capture. Vital only reads preview luminance frames.
- Frames are decoded in-process by the ZXing isolate and are not uploaded,
  logged or saved. Confirmed barcode/item associations are intentionally saved
  in encrypted SQLite, as described below. No image, barcode or match is
  uploaded or used for OCR or medical inference.
- The debug APK still carries the Flutter tool's debug `INTERNET` permission;
  the production main manifest does not add one for scanning.
- Linux builds compile the FFI library but the camera package has no Linux
  implementation. The scanner reports unavailable and keeps manual entry and
  search available. No desktop camera claim is made.

## Data and exit path

Associations are a bounded guarded setting keyed by canonical GTIN-14:
`barcode_links` in the encrypted SQLite `setting` table. Each record keeps the
item ID plus the reviewed name, form and strength and the confirmation instant.
The bound is 200 links total and 8 per substance. No schema migration is added.
Reader removal leaves ordinary substance records and history untouched; only
the optional barcode links become unavailable and can be re-linked.

The camera surface is behind `barcodeCameraBuilderProvider`, so a replacement
decoder can be adopted without changing the parsing, association, review or
guard layers.

## Verification

- `test/domain/barcode/gtin_test.dart`: check digits, leading zeros, EAN-8,
  UPC-A, EAN-13, GTIN-14, GS1 AI 01, symbology prefixes, repeated and distinct
  detections.
- `test/data/barcode_links_test.dart`: encrypted guarded setting, exact review
  snapshot, idempotence, conflict/replace, per-item and total bounds, item
  revision and commit guard, corruption and missing item.
- `test/barcode_scan_panel_test.dart`: linked review, explicit link, duplicate
  and multiple detections, manual entry, permission denial, foreground pause,
  route disposal, lock, dataset replacement, changed item, replace and missing
  link.
- `test/platform/barcode_decoder_test.dart`: real ZXing C++ decoding of
  generated EAN-13, EAN-8, UPC-A, leading-zero and GS1 Code 128 samples plus a
  two-symbol frame. Default runs skip; the evidence command sets
  `VITAL_BARCODE_NATIVE=1` and `LD_LIBRARY_PATH` to the built Linux bundle.
- `flutter build apk --debug` succeeded with `libflutter_zxing.so` for the
  packaged ABIs; APK permissions were inspected to confirm microphone/storage
  removal.
- `flutter build linux --debug` succeeded.
- Whole-project `flutter analyze` and formatting passed.

Limits: no physical Android device is attached. Camera permission prompts,
autofocus, torch, frame rate, thermal behaviour, TalkBack camera semantics and
real pack decoding were not device-tested. The scanner's confirmation rule is
the owner-approved "confirm once, then Use": the first link requires a reviewed
Link; every later scan shows the current saved identity and requires Use. No
national catalogue lookup or inferred product match is claimed.
