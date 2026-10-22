# Backup history

D21a adds a compact last-save summary and an optional History disclosure to the
canonical Backup page. The newest 20 local receipts distinguish archive checking
from an acknowledged OS save. Each receipt contains the archive SHA-256, exact
byte count, schema, record/item/file counts and full local dates. No password,
key, destination path or private record text is retained. Fresh restore
generations hide receipts imported from an earlier dataset. Automatic backups,
destination retention and password availability remain D21 lifecycle decisions.

History lives in existing encrypted settings, merged atomically across database
connections. A failed receipt write cannot change an actual save into a failed
save or offer a retry against a deleted staged archive. The page displays a
separate warning. Cancelled/failed saves do not acquire a confirmed-save receipt;
archive validation alone never becomes a saved-backup claim. Receipts cannot
prove that an external copy still exists or is restorable now.

The root read the Flutter expert, architecture, codebase-memory, unit/widget
testing, responsive layout, UI UX Pro Max, static analysis, both app-copy and
verification skills. The expert state/widget references, UI pre-delivery rules,
interaction blueprint and Backup/Restore rollout row were applied. Current
[Riverpod async presentation](https://riverpod.dev/docs/how_to/pull_to_refresh)
and [Flutter MediaQuery](https://api.flutter.dev/flutter/widgets/MediaQuery-class.html)
documentation were consulted. The pinned stack overrides dated generic examples.

Verification: 66 focused backup/store/controller/lifecycle/motion checks passed;
a subsequent 11-test Backup UI/history run covered the final full-date copy and
bookkeeping warning. These runs overlap; counts are run results, not a summed
unique-test claim. Whole-project analysis and `git diff --check` passed. Tests
cover encrypted reopen, bounds, merging, concurrent connections, lock/generation,
invalid history, real archive validation, save/cancel/failure, failed receipt
persistence, guarded cleanup, disclosure/error recovery and live reduced motion.

UI verification found two shared wrappers that reparented an open page/surface
when reduced motion changed. Stable route wrappers and keyed surface content now
retain disclosure and form state while bypassing animated sizing. The pinned
Flutter renderer asserts when a zero-duration AnimatedSize changes dimensions,
so reduced motion still bypasses that renderer rather than simulating animation.

- [Light](light-backup-history.png)
- [Dark](dark-backup-history.png)
- [Light, 320 px and double text](light-backup-history-narrow.png)
- [Dark, 320 px and double text](dark-backup-history-narrow.png)

Synthetic captures use the real Backup route with device-safe insets. This host's
test gateway truthfully reports file saving unavailable; real saved-file and
archive checks use the service test's copy destination. Larger content remains
in the page's single scroll owner. Physical-device screen-reader, external-file
retention, delivery and measured performance acceptance remain open.
