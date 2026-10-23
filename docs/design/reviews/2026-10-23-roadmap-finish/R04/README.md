# Local pack scanning

R04 implements the owner-approved suggestion-with-confirmation boundary for
barcode scanning. It adds no catalogue barcode index and does not claim a
national medicines lookup. A decoded number can only resolve to a user-confirmed
link to one saved substance.

## Entry and flow

`Scan` appears in the existing quick medication chooser (`/unplanned`) beside
the unchanged manual search and `Create` action. The reviewer's decision removed
the catalogue-picker entry because that picker has no admitted barcode source.
The chooser keeps its selected day, plan flag and suggested time; `Use` opens the
existing dose or plan form with that context.

1. The camera opens in the same task route. Manual `Enter` is always available.
2. A frame is reduced to distinct valid GTIN/EAN/GS1 numbers. Repeated
   detections and equivalent EAN/UPC forms collapse; distinct numbers become an
   explicit choice. No result is selected automatically.
3. A confirmed link shows the **current** saved name, form and strength. `Use`
   rechecks the item revision, app lock, route and dataset generation before
   opening the existing dose form. Camera output never records a dose, creates
   an item or changes stock.
4. An unlinked code opens a bounded saved-substance search. Choosing a substance
   shows its full identity and requires an explicit `Link` after rechecking the
   item and detail revisions. The link is written to the encrypted setting store.
5. `Change` supports an explicit relink. A code already linked to another
   substance shows that identity and requires `Replace`; ambiguity never picks
   one.
6. `Use` on changed details refreshes the review and requires `Use` again.

## States

The panel has explicit camera, manual-entry, multiple-code, ambiguous-link,
linked review, unlinked search, link review, replace, permission denied,
camera unavailable, invalid check digit, unsupported code, unreadable links,
missing substance, link limit, link failure, app lock, foreground pause,
dataset replacement and stale-item states. `Cancel` returns to the unchanged
manual chooser. Every stage has a one- or two-word heading and one-word command.

## Evidence

- Parser/check-digit/GS1 tests: `test/domain/barcode/gtin_test.dart`.
- Guarded encrypted association tests: `test/data/barcode_links_test.dart`.
- Scanner lifecycle, all outcomes, confirm/replace/Use and chooser entry:
  `test/barcode_scan_panel_test.dart`.
- Real decoder fixtures:
  `LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib VITAL_BARCODE_NATIVE=1
  ./tool/flutterw test test/platform/barcode_decoder_test.dart`.
  Generated EAN-13, EAN-8, UPC-A, leading-zero and GS1 Code 128 samples plus a
  two-symbol frame are decoded by the bundled ZXing C++ library.
- Captures in this directory: both themes at 390 px and 320 px/2x text for the
  camera, linked review and unlinked search, plus permission denial at 390 px.
  The camera area is a synthetic host preview; no physical camera was attached.
- Android debug build includes `libflutter_zxing.so`; merged permissions retain
  `CAMERA` and remove microphone and storage permissions. Linux debug build
  succeeds but the camera is unavailable there by design.

## Limits

- No physical Android device: permission prompts, camera preview, autofocus,
  torch, frame rate, thermal behaviour and TalkBack camera semantics remain
  unverified.
- Native Android compile and packaged-library inspection passed, but the lead
  owns the final integrated compile.
- The scanner does not choose a dose, timing, stock effect or catalogue product.
  Camera frames are not saved or uploaded. Confirmed barcode/item links are
  retained in the encrypted database; nothing is uploaded or used for OCR.
- The real-decoder test skips unless the built native library is supplied on
  `LD_LIBRARY_PATH`; that is a host-runner requirement, not a production path.

## Lead integration

The direct API lane stopped with Insufficient Balance. The lead completed
atomic revision/owner/setting-snapshot writes, concurrent-update refusal,
privacy deletion of saved links, current custom-profile review, lock/background/
route invalidation and fencing of callbacks from a retired camera instance.
Supported GS1 suffixes are deliberately bounded to expiry (17), lot (10) and
serial (21); unknown or malformed element strings use manual digits entry.
Neither lot nor serial values are retained.

Final verification includes 59 parser/association/store/privacy checks,
17 scanner UI/lifecycle checks, actual native ZXing fixtures, both-theme
captures, clean analysis, final integrated Android debug compilation and a
real Secret Service Linux boot. The packaged decoder exists for arm64-v8a,
armeabi-v7a and x86_64. Final APK inspection confirms CAMERA and absence of
microphone/external-storage permissions. INTERNET belongs to Flutter's debug
manifest; ACCESS_NETWORK_STATE is also present in the merged APK. Scanning
adds no uploads. Exact open-source notices and the release preflight pass;
physical-camera acceptance remains open.
