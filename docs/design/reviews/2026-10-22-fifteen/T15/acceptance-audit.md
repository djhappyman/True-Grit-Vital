# Acceptance audit: original 28 steps

22 October 2026. Audit baseline `cdefb2a`; this checkout is `bc14ce6` (assignment docs only). Graph generation `2026-10-22T22:17:00Z`, Tier 3 bounded. T01–T14 were concurrent and are not counted as shipped; the lead reconciles final status. Read-only audit: no app/test/spec edit, no full suite, no remote action.

**Status vocabulary.** Host means code, focused host tests and dated evidence exist. It does not mean physical-device, measured-performance, policy or release acceptance. Every original ticket remains `in-progress`; the saved inventory in `tool/release/obligations.json` reports 69/78 stories implementation-done, 60 host-tested and 18 with open verification; 18/20 screens implemented (S01 Profile, S02 Unlock partial), 7/8 sheets; 12 acceptance obligations open; gates 3 partially verified and 5 open. These are recorded inventory states, not a freshly measured completion percentage.

## Original steps 01–28

| Step | Shipped host capability and current evidence | Remaining obligation |
|---|---|---|
| 01 | Shell, routes, Riverpod composition: `tool/verify`, `lib/app/vital_app.dart`, `docs/implementation/01-shell.md`; emulator first launch in `02-android-runtime.md` | G01 CI destination, physical launch and signing host; US66/US69 open |
| 02 | Encrypted store, exact quantities, corrections/Undo, drafts: `lib/data/record_store.dart`, `lib/domain/records.dart`, `02-record-store.md` | Android KDF/rekey measurement, power loss; packaged backup policy lacks physical restore proof |
| 03 | Superseded by the 20 October single-user correction. Single `meId` feed; legacy multi-person data rejected (`586eaa1`) | Do not deliver multi-adult UI; retain rejection/identity tests. Obsolete criteria, not missing code |
| 04 | Optional lock and encrypted private drafts: `lib/app/app_lock.dart`, `lib/domain/drafts/`, `04-private-drafts.md` | Real biometric/PIN fallback, background/app-switcher, draft recovery on device; US63 partial |
| 05 | Custom entry, picker, stale-reply guards and immutable source snapshots: `lib/features/catalogue/catalogue_picker.dart`, `05-catalogue-gate.md` | **G05 open:** no production corpus or source terms. US07/M02 partial; blocks first usable release and 27 |
| 06 | Count, timed, PRN, preview and shared resolver: `lib/domain/scheduling/daily_resolver.dart`, `06-integrated.md` | D11 tolerance and device checks; no OS delivery claim in this step |
| 07 | Native AlarmManager/NotificationManager engine, Taken/Snooze/Skip, opaque action capture: `lib/platform/reminders.dart`, `android/app/src/main/kotlin/dev/truegrit/vital/ReminderEngine.kt`, `07-reminder-native.md` | Physical locked/background/terminated, permission and OEM cases; documented rejection of flutter_local_notifications is bounded, not a release pass |
| 08 | Selected/alternate day, week/month, annual and short-month rules: `calendar_pattern.dart`, `08-integrated.md` | Device/DST/travel evidence |
| 09 | Elapsed intervals and qualifying actual anchors: `interval_resolver.dart`, `09-integrated.md` | Device clock/zone recovery |
| 10 | Pause/resume with preserved or restarted pattern: `pause_pattern.dart`, `10-integrated.md` | Device evidence |
| 11 | Phases, exceptions, finite ends and moved slots: `phase_plan.dart`, `11-integrated.md` | Device evidence |
| 12 | Exact stock ledger, containers, restock/waste/adjustment, opt-in low-stock notices: `lib/domain/stock/`, `12-integrated.md` | Physical notice delivery; US40 partial |
| 13 | Mixed products, one physical outflow and immutable labels: `lib/domain/products/`, `13-integrated.md` | Device evidence |
| 14 | Atomic combined logging and optional sites/history: `lib/data/combined_store.dart`, `14-integrated.md` | Device evidence |
| 15 | Cycle/course events, membership and end review: `lib/data/event_store.dart`, `15-integrated.md` | Device evidence; no discontinuation advice claimed |
| 16 | Protected attachments, preview, pins and M08 actions: `lib/data/attachment_store.dart`, `lib/features/attachments/attachment_pages.dart` | Real picker/files, crash cleanup, handoff lifetime and share receivers; T02 in flight |
| 17 | Bounded History, calendar, exact-zone display, 12/24-hour preference: `lib/data/history_store.dart`, `17-history-ui.md` | D19 on-time/late indicators; physical performance |
| 18 | Bounded interactive charts and source drill-down: `lib/domain/charts/`, `18-chart-ui.md` | Measured frames/memory, TalkBack/table alternative |
| 19 | Manual panels, observations, ranges, unknown markers, attachments and trends: `lib/data/supporting_store.dart`, `19-supporting-ui.md` | Device evidence; OCR is not required for manual entry |
| 20 | R01 substance summary, exact totals, embedded fonts, text alternative: `lib/reports/r01_summary_template.dart` | G04 viewer/save contract; device memory, cancellation, low storage; no PDF/UA claim |
| 21 | R02 history and R03 event templates, pagination and distinct states: `lib/reports/templates/` | Large-report device checks and format review |
| 22 | Versioned JSON/CSV exports with exact provenance: `lib/domain/exports/`, `lib/data/export_store.dart` | Real SAF/save/share, cancellation and size limits on device |
| 23 | Password-protected coherent backup, Argon2id/HKDF/XChaCha20-Poly1305: `lib/backup/backup_service.dart`, `lib/domain/backup/backup_crypto.dart` | G04 archive-format review, KDF measurement, storage pressure, power loss |
| 24 | Staged validation, confirmed replacement, fresh generation, rollback/startup recovery: `lib/restore/restore_activation.dart` | New-device recovery with files; physical recheck of system backup/transfer |
| 25 | Scoped deletion/archive, settings, local help, notices, bounded redacted diagnostics: `lib/app/privacy.dart`, `lib/features/settings/` | G07 privacy/authority wording; device deletion and app-switcher checks |
| 26 | Bounded reconciliation, epoch handover, capacity and honest health panel: `lib/app/reminder_reconciler.dart`, `lib/app/reminder_health.dart` | Reboot/force-stop/OEM/clock/idle-wakeup evidence; receipt pruning policy |
| 27 | Not started as a pilot | Blocked by 05, 21, 26 plus G05/G06/G07, CI, TalkBack, large text, measured budgets, catalogue and physical recovery |
| 28 | Not started as a public release | Owner signing, publisher/territories, licence choice before publication, store claims, notices, migration/recovery notes |

## Design gaps D01–D27

`D01–D05` host integrated/verified (Today, search/filters, summaries, overview, shared components). `D06–D08` and `D10` host verified; `D09` integrated on host (week/favourites, status counts, setup/instructions, presets, context/skip reasons). `D13`, `D14`, `D20` and `D25–D27` host verified; `D16–D18` and `D23` host integrated with evidence. Physical gates remain open.

| Gap | State and factual boundary |
|---|---|
| D11 | Partial. Versioned authored plan instructions are saved, but **food/bedtime requirements and timing tolerance are not defined or stored**. `plan_form.dart:742/894` and ARB `screenScheduleTolerancePreview`/`screenScheduleRequirementsBody` say so |
| D12 | Partial. Sound/vibration, Android channel variants and OS-mute guards exist; **follow-up timing is absent** (`screenScheduleFollowUp` says so). Physical delivery open |
| D15 | Partial. Opt-in Android stock notices exist; **barcode/pack scanning is backlog** (`screenStockGaps`), device delivery open |
| D19 | Partial. Calendar, day cards, filters and week/month aggregates exist; **on-time/late classification awaits D11** |
| D21 | Partial. Manual encrypted receipts distinguish check from confirmed save; **automatic destination/retention/key/interruption lifecycle is undefined** |
| D22 | Backlog. No FHIR/HL7 mapping; UI truthfully points to structured export (`screenPanelFhirUnavailable`) |
| D24 | Device gate open. `glassValidatedProvider` is hard `false`; opaque/reduced-transparency fallback composes |

## Gates and release evidence

`G01` open (toolchain verified; CI destination, signing host and human-owned release terms open). `G02` partial (encrypted engine and populated migrations host/emulator; Android KDF, key recovery and transfer physical proof open). `G03` partial (host cases recorded across implemented scheduling families; physical DST/travel and native reconciliation evidence open). `G04` partial (archive format review, renderer memory, destination limits, power loss open). `G05` open. `G06` open (no physical reference device or adopted numeric budgets; US68 open). `G07` open. `G08` open.

- **Signing:** `android/app/build.gradle.kts` has no release `signingConfig` and fails `assembleRelease`/`bundleRelease` deliberately; debug signing only.
- **System backup:** `AndroidManifest.xml` sets `allowBackup="false"`; legacy and modern rules exclude all nine domains, and decoded APK evidence exists. Actual OEM backup/transfer restore remains untested.
- **Recovery:** emulator missing-envelope/missing-database checks pass with preserved hashes (`tool/check_android_recovery.py`); physical power-loss and process-death proof remain open.
- **Accessibility/performance:** TalkBack, keyboard, maximum text, reduced effects, sustained glass and measured frame/memory/battery have no current physical run. Old test-count and screenshot records are dated host evidence, not this proof.
- **CI/pilot/public:** no hosted workflow (`.github/workflows` absent); no pilot or signed public artifact. The published `v0.1.0-alpha.1` GitHub debug prerelease is not a production release; store publication remains unauthorised.
- **Later work:** Linux is a development/iteration target, not a validated release; iOS, Windows, macOS, optional OCR, widgets, deeper comparisons and web have no implementation or host validation here.

## Findings and next decisions

1. **Tracker debt, not missing code.** All 28 tickets are `in-progress`; steps 17–28 have zero ticked boxes although 17–25 have host implementations and evidence. Step 03's checks are obsolete after the single-user correction. Reconcile status from evidence, not old ticks.
2. **No new functional defect found in this document/source audit.** D11, D12, D15, D19, D21, D22, D24 and G05 are genuine open scope; the interface labels each unavailable capability honestly rather than faking it, and observations remain explicitly `Coming soon` by owner request. Minor hygiene only: `screenSettingsAutoBackup` and `screenSettingsFhir` ARB keys are currently unreferenced (no dead settings row is rendered).
3. **First blocking decision: G05 catalogue.** Human-owned dm+d/TRUD terms, exact source/version and attribution must be cleared before 05 can be called complete or 27 can start. RxNorm is a different scope, not a UK substitute.
4. **Then D11 → D19:** define timing tolerance (allowed lateness, display, no clinical inference), then reuse it for on-time/late indicators. Keep exact planned/actual distinctions.
5. **Remaining owner choices:** D12 follow-up policy, D21 automatic-backup lifecycle, D22 FHIR/HL7 format, D24 measured glass, G07 signing/publisher/territories. G06 physical workloads must be adopted before reliability or performance claims.
6. **Concurrent work:** T01–T14 address backup isolation, attachment authority, report date/seed validation, catalogue search, presets, export date shortcuts, trend source return, pre-paged movement filtering, metadata diffs, site context, plan preview, quick-entry dates, privacy confirmation and reminder-cancellation copy. Final acceptance must be rechecked after the lead integrates them; this audit does not credit them.

Skills read: `flutter-expert` (SKILL plus riverpod-state, widget-patterns, gorouter-navigation, performance, project-structure), `codebase-memory`, `verification-before-completion`, `dart-add-unit-test`, `dart-run-static-analysis`, `flutter-add-widget-test`, `flutter-apply-architecture-best-practices`, `flutter-build-responsive-layout`, `accessibility-compliance`, `vital-mobile-copy`, `better-writing`, `interaction-design`, `ui-ux-pro-max`. Graph coverage was rechecked for the cited `lib/` and Android paths; `tool/verify`, `app_en.arb` and the gitignored evidence docs were read directly. Docs/implementation evidence and `.scratch` are gitignored by design and were read from the parent; source citations resolve in this checkout.


## Lead reconciliation, 23 October

T01–T14 are now integrated with focused host verification; T15 is the completed
bounded audit. The [final batch review](../README.md) records concrete outcomes,
combined checks and remaining work. The baseline inventory counts and gate
states above are historical evidence, not updated completion percentages. No
physical, clinical-policy, catalogue-admission or distribution gate was closed
by this integration.

## Roadmap follow-through reconciliation

The later [23 October batch](../../2026-10-23-roadmap-finish/README.md) supersedes
the baseline design-gap findings above: D11/D19 now retain user-set timing
windows and food/bedtime labels; D12 adds optional follow-ups; D15 adds confirmed
local barcode links and real decoding; D22 adds reviewed FHIR R4 JSON export.
D24 has a runnable measurement harness but remains device-gated. D21 automatic
backups were deferred by the owner; manual backups remain the current scope.
Catalogue source admission, physical recovery/delivery/accessibility and owner
release gates are unchanged. The older counts and unavailable-copy citations
above describe that audit's baseline, not the current implementation.
