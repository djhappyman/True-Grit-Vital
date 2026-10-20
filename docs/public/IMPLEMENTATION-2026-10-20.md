# 20 October implementation

Ten DeepSeek work packages have been integrated into the main checkout, followed by lead review, integration fixes and verification. This checkpoint adds usable reports, exports, protected backup/restore, privacy/settings/help, artifact handoff and reminder health. It also includes the previously reviewed supporting-record repair round that was still uncommitted.

This is implementation progress, not pilot or release acceptance. The readiness inventory still reports eight gates open or partly verified, 18 stories open/partial and 12 acceptance obligations awaiting acceptance evidence.

## Ten work packages

| Task | Delivered |
|---|---|
| T01 — supporting records | Locale-aware exact input, note-only observations, source attachment linking with frozen revision/version, conservative comparison identity and clearer recovery copy. |
| T02 — R01 pipeline | Coherent person-scoped capture, exact totals, embedded-font substance-summary PDF, structured text alternative, preview, progress and cancellation. |
| T03 — structured export | Person/date/content-scoped JSON and CSV, exact quantities/revisions, private defaults and saving the reviewed bytes. |
| T04 — protected backup | Versioned authenticated archive, Argon2id/HKDF/XChaCha20-Poly1305, coherent encrypted snapshot, attachment validation, self-validation, progress/cancellation and password-loss guidance. |
| T05 — Save/Share | Bounded private streaming staging, checksums, Linux save and Android save/share offers, expiry/cleanup and truthful unsupported/busy/failure states. |
| T06 — R02/R03 | Detailed-history and event-review templates, selected-item filters, separate recorded/skipped/unrecorded states, event membership/use state, quantity/product grouping and selectable report UI. |
| T07 — restore | Protected intake, staged validation/preview, explicit full replacement, migration/rekey, fresh generations, stale-action rejection, journalled activation/rollback and startup recovery. |
| T08 — settings/privacy/help | Settings inventory, scoped archive/reactivation/deletion, local help and sources, full bundled notices, bounded redacted diagnostics and accessible interactions. |
| T09 — reminder health | Epoch handover after restore, bounded convergence, capacity/cancellation diagnostics and a visible health/repair panel. |
| T10 — readiness tools | Obligation/capability inventories, exact dependency/notice audit, release preflight, fail-closed signing and isolated boot tooling. Acceptance and distribution gates remain open. |

All ten workers used OpenCode with `opencode-go/deepseek-v4.1-flash` in separate worktrees. Each supplied baseline and skill-access evidence. Required sources included `flutter-expert`, the applicable official Flutter/Dart architecture/test/analysis skills and, for product text, `vital-mobile-copy` plus `better-writing`. Installed files were read directly where a native skill loader was unavailable. The lead merged owned deltas and shared wiring rather than applying worker diffs over one another.

## Integration repairs

The lead connected real report/export/backup destinations and the R02/R03 selection UI, then corrected issues found during review:

- Immutable reviewed PDF/export buffers, operation identities, lock/disposal handling and rejection of late success after Cancel.
- Transaction-bounded report capture; stable person/date links from History; release of attachment pins after cancellation or navigation.
- R01 table headers that repeat at actual page boundaries, replacing fixed row-count repetition.
- R03 item/unit/strength grouping and event-only source references, with bounded use-period reads.
- Backup capture/maintenance exclusion, truthful discard failures, actual destination size limits and historical quantity validation.
- Clearing old generated previews/staging before deletion or replacement, including the existing profile form's delete path.
- Preserving the installation app-lock preference during restore; backpressured file copying; atomic rename without deleting the live target on failure; one verified rollback path.
- Linux startup admission of private backup/restore staging and visible recovery outcomes.
- Reminder health that does not claim a prepared-through date after failed, deferred or blocked reconciliation; late capability reads retain completed repair evidence.
- Correct Gradle task-graph validation, complete legal-reader assets and current public capability metadata.

Schema 21 remains current. These new report/export/backup/restore/settings modules add no further migration. The commit also carries the earlier supporting-record query/presentation and durable recovery migrations/fixes.

## Verification

The final source manifest and command logs are retained locally under `output/implementation/ten-tasks-2026-10-20/`.

| Check | Result |
|---|---|
| Full Flutter suite | 1,433 passed; one explicit keyring skip. |
| Dart formatting and analysis | 375 files, no formatting changes; clean application and vendored-hook analysis. |
| PDFium integrity hook | Six cases passed. |
| Release/preflight unit tests | 14 passed; automated preflight passed. |
| Separate-process recovery suites | All 15 suites passed, including backup interruption and restore activation/rollback checkpoints. |
| Native Kotlin cases | Seven artifact-transfer and 29 reminder-engine cases passed. |
| Android compilation | `:app:compileDebugKotlin` passed. |
| Native Linux app | Passed with real isolated Secret Service storage; its temporary key/data were removed. |
| Normal Linux debug bundle | Built successfully at `build/linux/x64/debug/bundle/vital`. |
| Release-signing negative check | Correctly refused release task execution without owner-supplied signing. |

The source fingerprint is `ace944768dcabefade00f86eb4606160db3b78e2f7ecb7d8470b1a000fac4b90` across 524 runtime/test/tool/dependency files. Source files remained unchanged during the final verification run. The local keyring unit skip is explicit; the independent native smoke exercised its unique real Secret Service key.

The isolated native Linux test uses real encrypted SQLite and a unique Secret Service namespace. It reopens persisted records, checks data routes, generates an export preview and an embedded-font report, creates/self-validates a backup and rechecks bootstrap with staging present. Successful runs remove only their own records/key.

Final production-renderer PDF samples were inspected with embedded Noto Sans: R01 six pages, R02 nine pages and R03 four pages. Long names wrap, page identity repeats, and extracted text stays inside page bounds. These are synthetic host samples, not device or PDF/UA acceptance.

Dependency admission adds `pdf` 3.13.1 and `cryptography` 2.9.0 plus the PDF transitive packages. Noto Sans assets and licences are retained. The exact resolved audit covers 112 hosted packages; the in-app reader includes package, native, SDK and font notices. `intl` 0.20.3 became direct without an upgrade. The generated legal bundle deliberately preserves upstream whitespace.

See [backup format and boundaries](BACKUP-FORMAT.md), [current status](STATUS.md) and [verification commands](../../README.md#verification).

## Still needed

- Physical Android/emulator launch and real save/share receiver behaviour; no Android device is connected here.
- TalkBack, keyboard/large-text acceptance, performance budgets and save-under-load measurements.
- Android KDF/rekey/encryption, storage exhaustion, large-file, locked/background and power-loss evidence; G04 review of the concrete archive format.
- OEM permission/battery/reboot/force-stop/time-change reminder evidence. Native refill reminders remain incomplete.
- Catalogue source/access clearance; OCR stays optional later work.
- Publisher, territories, professional-use privacy/retention wording, store claims and production signing.

About 1.7 GiB of known disposable worker build caches were removed. Worker source/evidence, package configuration, installed tools/skills and the current Linux runtime were preserved.

Current bounds are material: Android outbound staging is 512 MiB, Linux save is 64 MiB, source picking lists the 50 most recent files, report item picking is bounded to 500, and report/export capture rejects excessive selections. PDFs have a structured text alternative and are not tagged PDF/UA. Gates stay open where only host evidence exists.
