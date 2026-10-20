# True Grit: Vital

**A local-first substance tracker for adults who want a clear record of what they use, when they use it, and what they have left.**

Vital brings medicines, supplements and other substances into one place: doses, schedules, reminders, stock, use periods and history. It is a single-user app, with one local profile and one feed. Optional lab panels and observations provide context alongside recorded use.

The goal is less guesswork and better-organised information for personal review or conversations with a healthcare professional. Vital records information; it does not diagnose conditions, recommend treatment or establish that a substance caused a change.

## Project status

This is an early development project, public from its first source release. Android is the primary target. Linux runs the same mobile-oriented interface for convenient development. The interface is still being simplified and redesigned; shared components make changes consistent across screens.

Implemented areas include:

- One local profile, encrypted storage, private drafts and optional Android app lock.
- Substances, exact quantities, corrections, Undo, containers and stock.
- Daily, weekday, calendar and interval schedules, pauses, phases and Android reminders.
- Ready-mixed products, combined logging, optional sites, cycles and courses.
- Protected file/photo attachments, bounded image/PDF previews and explicit sharing.
- History, a medication calendar, charts and source-record inspection.
- Manual lab panels and supporting observations, with original values, units, source links and ranges.
- R01 substance summaries, R02 detailed history and R03 event reports, with PDF/text previews and reviewed-artifact saving or sharing.
- Date-filtered JSON/CSV exports with exact quantities, corrections, private defaults and reviewed-file saving.
- Password-protected full-installation backups, staged restore, fresh dataset generations and interruption recovery.
- Settings, your profile, record deletion, local help, bundled licences and bounded redacted diagnostics.
- Reminder health, bounded reconciliation and release preflight/evidence tools.

**Not a finished or clinically validated release.** The new flows are implemented and host tested. Physical-device accessibility, performance, Android lifecycle and destination behaviour, backup-format review and distribution clearance remain open. See [current progress and next work](docs/public/STATUS.md) and the [20 October implementation report](docs/public/IMPLEMENTATION-2026-10-20.md).

There are no remote user accounts or cloud record synchronisation. Watch integrations and a general wellness dashboard are outside the current scope.

## Design references

UI contributors should start with the [shared component framework](docs/design/components.md) and [Stitch design references](docs/design/README.md). Full-resolution screenshots, original HTML and design metadata are kept in the repository. Reusable panels, headers, typography, fields and controls provide the visual foundation for implemented features. UI pull requests should identify the reference screen and include comparison screenshots.

## Prerequisites

- Git and **Flutter 3.47.7 stable with its bundled Dart 3.13.5**. The pin is in [`.flutter-version`](.flutter-version).
- Python 3 for verification scripts; a POSIX shell for `tool/` wrappers.
- Android: a compatible JDK 17+ and the Android SDK/toolchain required by this Flutter release. Install the required SDK components and accept their terms yourself.
- Linux: Flutter Linux build dependencies (C/C++ compiler, CMake, Ninja, pkg-config, GTK 3 development libraries), plus an unlocked Secret Service keyring. Runtime helpers include `secret-tool`, `gdbus`, `flock`, `install`, `chmod`, `sync` and `cat`. See [Linux prerequisite notices](docs/implementation/licenses/linux-system-prerequisites.txt).

Install the pinned SDK using the [official Flutter installation instructions](https://docs.flutter.dev/install) and [SDK archive](https://docs.flutter.dev/install/archive). Run `flutter doctor -v` using that SDK to diagnose host requirements.

## Get started

```sh
git clone https://github.com/djhappyman/true_grit_vital.git
cd true_grit_vital

# Set this if the pinned SDK is not at ~/.local/share/flutter-3.47.7.
export VITAL_FLUTTER_SDK=/absolute/path/to/flutter-3.47.7

./tool/flutterw pub get --enforce-lockfile
./tool/flutterw devices
```

`tool/flutterw` checks both Flutter and Dart versions. An older system-wide `flutter` can fail dependency resolution even if it runs other projects successfully. Keep `pubspec.lock` intact unless intentionally updating dependencies.

### Linux debug app and hot reload

```sh
./tool/flutterw run -d linux
```

Keep the terminal open. Press `r` for hot reload, `R` for hot restart and `q` to stop. Linux intentionally shares the mobile UI. Android authentication and native reminders are not implemented on Linux.

### Android debug app

Start an emulator or connect an Android phone with USB debugging enabled, then select its ID from `devices`:

```sh
./tool/flutterw devices
./tool/flutterw run -d YOUR_DEVICE_ID
```

To compile an installable debug APK without launching it:

```sh
./tool/flutterw build apk --debug --no-pub
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`. This is a development build, not a signed production release. Release builds fail closed until owner-supplied signing is configured; the source tree contains no release signing material. App distribution still requires the documented release checks.

### Linux bundle

```sh
./tool/package_linux.sh
```

The complete bundle and archive are written under `output/linux/`. Keep its `lib` and `data` directories with the executable. The packaging script checks required libraries and includes dependency notices. It does not install system integration or change your keyring.

## Verification

```sh
# Formatting, analysis, native-asset hook checks, all Flutter tests,
# and process-interruption/recovery checks.
./tool/verify checks

# Individual checks during development.
./tool/flutterw analyze --no-pub
./tool/flutterw test --no-pub

# Also run native Android ledger tests and compile a debug APK.
# Requires the admitted Android/Kotlin toolchain and its cached compiler jars.
./tool/verify android
```

The checks use synthetic test records. Some native/keyring checks are explicitly opt-in. Passing host tests or compiling an APK does not replace physical-device testing.

Android integration tests are under `integration_test/`. Use a dedicated disposable emulator, not a phone containing records you rely on. Read `tool/check_android_integration.py --help` before running it; direct integration installation can affect test-app data.

## Data and security

Android uses a Keystore-backed key; Linux uses the desktop Secret Service keyring. Records and attachment originals use encrypted SQLite storage. Keep the database and its key intact: portable backup/restore is not implemented yet, and losing either may make records unrecoverable.

Do not commit real health records, exported files, credentials or signing keys. Security and recovery behaviour are still being tested; use synthetic data when evaluating early builds.

## Structure

- `lib/domain/`: record, schedule, quantity and comparison rules.
- `lib/data/`: encrypted persistence, revisions and migrations.
- `lib/app/`: shared state, routing and platform coordination.
- `lib/features/`: screens and feature interactions.
- `lib/ui/`: shared visual components; shadcn_flutter is the main control system.
- `test/`, `integration_test/`: automated checks and synthetic migration fixtures.
- `third_party/pdfium_dart/`: documented PDFium integration patch and pinned native assets.

Riverpod manages shared state, go_router handles navigation and Drift provides database access. Glass treatment can be introduced centrally; it is not applied throughout the current UI.

## Licence

Vital's original source is available under the [MIT licence](LICENSE). Dependencies and vendored/native components retain their own licences. Their notices are included in [docs/implementation/licenses](docs/implementation/licenses), with the PDFium patch described in [VITAL_PATCH.md](third_party/pdfium_dart/VITAL_PATCH.md).
