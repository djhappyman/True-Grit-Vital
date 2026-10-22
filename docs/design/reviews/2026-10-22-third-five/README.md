# Third five-task batch

22 October 2026, based on `55f84cf`. Four direct-API DeepSeek workers ran
concurrently with the lead, using isolated worktrees and the same specification,
Flutter/copy skills and interaction blueprint. No new dependencies or schema.

- [Backup receipt inspection](backup/README.md), lead: retained receipt filters,
  creation/check/save facts and one shared latest-save calculation.
- [Inventory sorting](d13g/README.md), DeepSeek and lead integration: explicit
  Name/Expiry ordering across the bounded filtered collection before paging.

- [Substance reports](reports-item/README.md), DeepSeek and lead integration:
  canonical report selection starts with exactly one substance. Invalid scope/date
  links stay in recovery, active drafts need Replace, and the scope notice follows
  the reviewed selection.

- [Stock source inspection](stock-source/README.md), DeepSeek and lead integration:
  Open resolves single/combined saved-dose identity and preserves nested stock
  context. Delayed lookup, lock, departure and duplicate-navigation guards apply.

- [Event History](d16d/README.md), DeepSeek and lead integration: open canonical
  event-filtered History, retain the named scope and return to the same event.
  Existing dated membership/event bounds are preserved, with no extra date window.

All five implementations are integrated and host verified. Task briefs, identities
and original results are retained locally under
`.scratch/vital-implementation/third-five-2026-10-22/`.

The lead reproduced the reported narrow option-sheet Escape failure before
repairing the shared component. Explicit initial focus and Escape handling now
return focus to the invoking button, verified across all four collection
filter destinations. Existing Back/Done, privacy and shared motion guards remain.

## Verification

Backup: four new checks, 24 existing backup/Settings/store/flow regressions and
clean analysis. Stock integration: 17 combined sort/store/backup checks passed.
The worker additionally reported 48 stock regressions; lead review inspected
the implementation and real light/dark captures, including narrow double text.
Final shared-options/sort/motion verification passed 15 checks after the fix;
an additional wide-popover Escape/focus/reopen check passed. Analysis was clean.

Timing tolerance, reminder follow-ups, automatic-backup lifecycle, scanning/
FHIR decisions and physical Android/accessibility/delivery/performance gates
remain open. Focused results do not establish a whole-suite or device pass.

Substance report integration: 69 focused item/event/report/overview checks passed
after the lead fixes, with clean project analysis. Additional isolated keyboard
and malformed-date checks passed. Both reported bugs failed before their fixes.

Stock source integration: after correcting the spinner caught during review, all
16 affected source/deferred-lookup checks passed. The 23 unchanged stock/history
regression cases passed in the earlier run that exposed that spinner failure.
Final project analysis was clean. No failed mixed run is counted as a suite pass.

## Final combined result

- 108 tests passed across the five feature slices, shared filter options, History
  date entry, event reports and motion. This is focused host evidence, not a
  whole-application suite claim.
- Final `./tool/flutterw analyze --no-pub`: no issues found.
- Native Linux debug build and real Secret Service boot/persistence/navigation/
  export/backup smoke passed. The unique secret was cleared and the temporary
  dataset directory removed. [Result](native-boot-result.json).
- The existing Drift debug warning during backup snapshot inspection also occurs
  in the previous batch's native log. It remains visible and was not suppressed.
- Real Flutter synthetic captures were reviewed in both themes, including narrow
  double text, full names/units, contextual commands and source/return paths.

The worker reported 154 event/History regression checks; lead integration added
name-lookup error/retry and registered-return validation, then verified all 14
focused event checks in the successful 108-test combined run. Existing dated
membership/event bounds remain authoritative. This run adds no inferred record
association and does not close physical-device or unresolved policy gates.
