# Development checkpoint

Vital is an unfinished Android-first app for adults who want to organise substance use, schedules, quantities and stock, including records kept locally for another adult. Optional blood-test panels and observations help organise supporting information without making medical recommendations.

## What is working

The implemented foundation covers encrypted local profiles and records; dose logging, corrections and Undo; complex schedules and Android reminders; stock and mixed products; cycles and courses; protected attachments; History, a calendar and exact source-backed substance charts.

The latest development round added initial manual supporting records. It preserves separate collection, report and entry dates, signed or qualified results, original units/ranges, missing results and source attachments. Comparisons are deliberately conservative: uncertain laboratory/method identities remain table-only, and measurements are not summed like doses.

The UI is a working development interface. Simplifying forms, reducing exposed detail and redesigning screens remain separate work, using shared components.

## What remains

Before expanding further, address the current supporting-record reviews: richer source-date handling, stable marker/laboratory identity, missing unit/range presentation, locale-aware input, note-only observations, accessibility and restart recovery for an uncommitted void action. Passing automated checks does not close these review findings.

The storage review also identified date-zone consistency issues, queries that scan a person's or metric's history before filtering, and missing upgrade-path coverage for new attachment/draft targets. These are known development limitations, not completed acceptance criteria.

Later planned work includes:

- Substance-summary, history and cycle/course PDF reports.
- Structured data exports.
- Protected backups, restore and migration recovery flows.
- Privacy controls and local help.
- Reminder recovery under real operating conditions.
- Physical-device accessibility, performance and lifecycle testing.
- Private pilot and public-release preparation.

The offline medicines catalogue still has an unresolved source/access gate. No NHS dm+d data is bundled merely because an adapter or search interface exists. OCR is a later optional feature, not a requirement for manual entry. Watches, remote accounts and general wellness expansion remain outside the current scope.

## Evidence boundaries

The schema19 publication checkpoint passed `./tool/verify checks`: 1,083 Flutter tests passed with one explicit skip, formatting and static analysis were clean, and the PDFium integrity and process-recovery suites passed, including supporting-record migration recovery. A separate checkout containing only published files resolved the locked dependencies and passed 55 scheduling tests and six PDFium integrity checks.

Android and Linux have compiled successfully at earlier checkpoints. This does not establish physical-device performance, TalkBack behaviour, every OEM reminder condition or production readiness. Existing development APKs use development signing. Portable backup/restore is not yet available.

Development is paused at the owner's request after this round. Public source publication does not mark the approved feature plan complete.
