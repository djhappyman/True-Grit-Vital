# Development checkpoint

Vital is an unfinished Android-first substance tracker for adults. It keeps your doses, schedules, stock, use periods, cycles/courses, history and reports. Lab panels and observations provide optional context. One local adult and one feed replace the earlier multi-person prototype.

## Implemented

The foundation includes encrypted records, corrections and Undo; private drafts; exact quantities and mixed products; schedules and native Android reminders; stock; protected source attachments; History, calendar and substance charts.

The 20 October integration adds:

- Supporting-record source linking, locale-aware numeric input, note-only observations, conservative comparison identity and durable void/restore recovery.
- R01 substance summaries, R02 detailed history and R03 event reports. Dates, items and optional context feed one captured PDF/text artifact for your profile. Source files are listed, not silently embedded in the report.
- Date-filtered JSON/CSV exports, with exact quantities and revisions and private notes excluded by default.
- Protected artifact saving and Android share offers. The same reviewed bytes and checksum reach bounded private staging; a share offer does not prove receipt.
- Authenticated full-installation backups and staged, explicitly confirmed full replacement. Validation, migration, fresh generations, stale-action rejection, previous-dataset rollback and startup recovery are implemented. The installation app-lock preference is retained.
- Settings, your profile, record deletion, help, catalogue attribution, full bundled notices and a bounded redacted local diagnostic log. No diagnostic uploader exists.
- Reminder health and bounded repair, with explicit incomplete/deferred/failed states.
- A machine-readable obligation inventory, dependency/licence checks, release preflight and isolated boot tools.

The interface remains a development UI. Host tests establish specific behaviour; they do not establish physical accessibility, clinical validity or production readiness.

## Verification

A real native Linux smoke uses encrypted SQLite and a unique Secret Service namespace. It verifies persistence, navigation, exports, report rendering with embedded fonts, backup creation/self-validation and bootstrap reopening with staging present. Its synthetic records and unique key are removed after success.

The single-user revision passed 1,427 host tests with one existing skip, all 15 separate-process recovery suites and the native Linux boot check. The combined test results, integration repairs and evidence boundaries are recorded in the [implementation report](IMPLEMENTATION-2026-10-20.md). Schema 21 remains current; the new report/export/backup/restore/settings work requires no further migration. The earlier supporting-record migrations remain part of this source checkpoint.

Android and Linux builds are checked separately. The current source tree refuses release builds until owner-supplied signing and G07 clearance exist. Debug builds use development signing. The earlier APK/upload request remains cancelled.

The shared [UI framework](../design/components.md) now applies Stitch-informed typography, containers, controls and page layouts to the existing features. Light mode uses a white canvas; dark mode follows the green-black reference palette. Navigation stays fixed at the bottom, and device safe areas are enforced centrally. The source PNG/HTML references remain in the repository. This presentation work adds no new tracking capabilities; glass retains its existing device-validation gate and opaque fallback.

The framework revision passed 1,432 host tests with one existing skip, including 33 existing routes in both themes, fixed-navigation checks and safe-area/large-text layout checks. The native Linux boot and normal debug build also passed. These are host checks; physical Android acceptance remains open below.

## Still open

- Physical Android boot, TalkBack, large text/keyboard acceptance and measured performance budgets.
- Real SAF/save/share receivers, locked/background behaviour, storage pressure and large-file limits. Android staging is bounded to 512 MiB; Linux saving currently buffers at most 64 MiB. The archive reader supports larger bounded inputs, which does not remove destination limits.
- Android KDF/encryption/rekey measurements, backup-format expert review and lifecycle/power-loss evidence. Host interruption tests cover process checkpoints.
- OEM battery, permissions, force-stop, reboot and time-change reminder behaviour. A prepared schedule is not proof of delivery. Native refill reminders remain incomplete.
- Publisher, territories, professional-use privacy/retention wording, store claims and production signing.
- The offline medicines catalogue source/access gate. No NHS dm+d corpus is bundled merely because an adapter exists.

OCR remains optional later work. Watches, remote accounts and a general-wellness dashboard remain outside scope. Some selections are bounded: supporting-source picking currently lists the 50 most recent files, report/export work refuses excessive source windows, and PDFs use an accessible structured text alternative rather than PDF/UA tagging.
