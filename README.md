# True Grit: Vital

**A clear, private record of the medicines, supplements and other substances you use, kept on your own device.**

Vital exists to make substance tracking clearer, with safety in mind. It helps you answer simple questions that are easy to forget: what did I take, how much and when? You note your doses and keep an eye on what you have left, and when you want to talk to a doctor or pharmacist, you choose a timeframe and share an exact, readable record. Knowledge is power, and an accurate record turns "I think I was taking it then" into something you can both look at together.

The aim is to support informed conversations with a doctor or pharmacist through accurate, useful records. Vital does not judge your choices or recommend what to take. It cannot verify that a substance, dose or combination is safe.

## What Vital can do

- Build your own substance list with custom names, exact amounts and clear units, including brand and product names and ready-mixed products recorded in one combined entry.
- Record injectable or oral forms, with a labelled strength per tablet, capsule or millilitre where you know it.
- Keep each mixed vial separate: its original powder amount, confirmed final volume and exact concentration, because different vials can differ.
- Store optional half-life details you enter yourself, with form, route and source, as reference information. Vital does not estimate blood levels.
- Plan multiple doses per day on flexible schedules: daily, chosen weekdays, calendar dates or intervals, with pauses and phases.
- Track cycles and courses as events, so a course can run its own dates while individual plans pause or resume.
- Review your full history with corrections and Undo, so changes stay visible rather than erased.
- Choose a timeframe and export it as a PDF report or a CSV or JSON file. You review, save and share it yourself. Nothing is sent automatically to anyone.
- Set dose reminders on Android. An unrecorded dose stays "not recorded" rather than being assumed missed. Gentle opt-in follow-up nudges are planned.
- Track routines around your doses with notes, food and context tags and skip reasons tied to each substance record. A monthly History summary shows recorded days and entries, with skips and voids kept separate.
- Manage your stock: current balances, in-app low-stock notices and simple adjust, restock and waste actions.
- Keep everything private: encrypted local storage, an optional app lock, private drafts and password-protected backups. There are no accounts and no cloud sync.

## Where the project stands

Vital is early in development, aimed at Android first (with a Linux build used for development). Most features above are implemented and tested on the development host, but these are still being built:

- **Follow-up nudges** after an unrecorded planned dose. Basic Android dose reminders exist today.
- **On-time and late labels** in history. Timing rules are still being defined.
- **Native low-stock notices** from the operating system. In-app stock notices exist today.
- **Automatic backups** on a schedule. Manual password-protected backups work today.

The app is not a finished or clinically validated release, and physical-device checks remain open. See the [development checkpoint](docs/public/STATUS.md) for current progress and the [implementation roadmap](docs/design/roadmap.md) for planned work.

## Your records are yours

Records and attachments are stored encrypted. Android protects the key with Keystore and Linux uses the desktop keyring. Keep the app and its key intact, because losing either may make records unrecoverable. Backups are password protected, and you need that password to restore, so choose it carefully and keep it somewhere safe. Security and recovery behaviour are still being tested, so use synthetic data when evaluating early builds and do not commit real health records to the repository.

## Contributing

Want to help? Start with [CONTRIBUTING.md](CONTRIBUTING.md), which points to the [interaction blueprint](docs/design/interaction-blueprint.md), the [shared components](docs/design/components.md) and the saved design references in [docs/design/README.md](docs/design/README.md).

<details>
<summary>Setup, building and verification</summary>

### Prerequisites

- Git and **Flutter 3.47.7 stable with its bundled Dart 3.13.5**. The pin is in [`.flutter-version`](.flutter-version).
- Python 3 for verification scripts and a POSIX shell for `tool/` wrappers.
- Android: a compatible JDK 17+ and the Android SDK/toolchain required by this Flutter release. Install the required SDK components and accept their terms yourself.
- Linux: Flutter Linux build dependencies (C/C++ compiler, CMake, Ninja, pkg-config, GTK 3 development libraries) and an unlocked Secret Service keyring. See [Linux prerequisite notices](docs/implementation/licenses/linux-system-prerequisites.txt).

Install the pinned SDK with the [official Flutter installation instructions](https://docs.flutter.dev/install) and [SDK archive](https://docs.flutter.dev/install/archive). Run `flutter doctor -v` with that SDK to diagnose host requirements.

### Get started

```sh
git clone https://github.com/djhappyman/true_grit_vital.git
cd true_grit_vital

# Set this if the pinned SDK is not at ~/.local/share/flutter-3.47.7.
export VITAL_FLUTTER_SDK=/absolute/path/to/flutter-3.47.7

./tool/flutterw pub get --enforce-lockfile
./tool/flutterw devices
```

`tool/flutterw` checks both Flutter and Dart versions. An older system-wide `flutter` can fail dependency resolution even if it runs other projects successfully. Keep `pubspec.lock` intact unless intentionally updating dependencies.

### Run the app

```sh
./tool/flutterw run -d linux
```

Keep the terminal open. Press `r` for hot reload, `R` for hot restart and `q` to stop. Linux shares the mobile UI. Android authentication and native reminders are not implemented on Linux.

For Android, start an emulator or connect a phone with USB debugging enabled, then run `./tool/flutterw devices`, pick the device ID from the list and run `./tool/flutterw run -d YOUR_DEVICE_ID`.

To compile an installable debug APK without launching it:

```sh
./tool/flutterw build apk --debug --no-pub
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`. This is a development build, not a signed production release. Release builds fail closed until owner-supplied signing is configured; the source tree contains no release signing material.

For a Linux bundle, run `./tool/package_linux.sh`. The bundle and archive are written under `output/linux/`. Keep its `lib` and `data` directories beside the executable.

### Verification

```sh
# Formatting, analysis, native-asset hook checks, all Flutter tests,
# and process-interruption/recovery checks.
./tool/verify checks

# Individual checks during development.
./tool/flutterw analyze --no-pub
./tool/flutterw test --no-pub

# Also run native Android ledger tests and compile a debug APK.
./tool/verify android
```

The checks use synthetic test records. Some native/keyring checks are explicitly opt-in. Passing host tests or compiling an APK does not replace physical-device testing.

Android integration tests are under `integration_test/`. Use a dedicated disposable emulator, not a phone containing records you rely on, and read `tool/check_android_integration.py --help` before running it.

### Code layout

- `lib/domain/`: record, schedule, quantity and comparison rules.
- `lib/data/`: encrypted persistence, revisions and migrations.
- `lib/app/`: shared state, routing and platform coordination.
- `lib/features/`: screens and feature interactions.
- `lib/ui/`: shared visual components; shadcn_flutter is the main control system.
- `test/`, `integration_test/`: automated checks and synthetic migration fixtures.
- `third_party/pdfium_dart/`: documented PDFium integration patch and pinned native assets.

Riverpod manages shared state, go_router handles navigation and Drift provides database access.

</details>

## Licence

Vital's original source is available under the [MIT licence](LICENSE). Dependencies and vendored/native components retain their own licences. Their notices are included in [docs/implementation/licenses](docs/implementation/licenses), with the PDFium patch described in [VITAL_PATCH.md](third_party/pdfium_dart/VITAL_PATCH.md).
