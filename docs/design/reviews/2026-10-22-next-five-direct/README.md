# Five-feature batch

22 October 2026, based on `0dab613`. Four concurrent OpenCode workers used
direct-API `deepseek/deepseek-flash`; the lead implemented guided restock and
reviewed the combined changes. No dependency or database schema changes.

- D13d: whole-collection Expired and Expires today inventory filters/counts.
  Unknown zones show unavailable status; cards use the same captured day.
- D14c: conditional stock run-out for fixed-planned elapsed intervals, through
  the existing resolver. Phase, pause, end and exact quantity rules remain;
  actual-anchored schedules remain unsupported. Expansion is bounded before
  allocating rows (50,000 occurrences, 366-day horizon).
- D17c: each disclosed lab trend value opens its original saved record.
  Identity, exact values, filtered return context and lock guards are retained.
- D21b: Settings Data shows the latest confirmed backup save receipt, with
  loading, retry and empty states. This does not confirm external file retention.
- D13e: Restock offers a new pack or an addition to the existing container.
  Both reuse the existing editors; the chooser writes nothing. Existing drafts
  remain authoritative and are explicitly identified when restored.

## Verification

Final host checks passed:

- 51 forecast/backup/settings checks, then 25 focused checks including the
  added high-frequency interval bound and Settings theme captures.
- 42 inventory/expiry/restock/route checks; 25 restock/stock/motion checks.
- Eight lab-source checks including identity/return encoding, both themes,
  320 px/2x text, lock, missing records and final captures. The other Labs
  suites passed 16 checks. Counts overlap and are not a unique suite total.
- Whole-project `./tool/flutterw analyze`: no issues found.
- Native Linux boot with the real Secret Service: exit 0; temporary namespace
  and directory cleanup succeeded. [Result](native-boot-result.json).
- Light/dark Flutter captures reviewed for [restock](restock/README.md),
  [backup status](backup-status/README.md) and [lab sources](lab-source/README.md).

Worker evidence is retained for [expiry](b998e8e8/README.md) and
[backup status](ca09f236/README.md). Briefs, skill access records and worker
results remain under `.scratch/vital-implementation/next-five-direct-2026-10-22/`.
The lead used the installed Flutter, codebase-memory, copy, layout, interaction,
testing and verification skills; all workers read the common required sources.

No physical Android delivery, screen-reader or measured performance claim is
made. Clinical timing, follow-up policy, automatic backup destinations/retention,
scanning and FHIR decisions remain open. No APK or release was created here.
