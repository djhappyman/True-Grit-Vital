# D13 and D14 stock evidence

Lane: paid DeepSeek. Worktree `t3-c3f47786`, base `9b9ce6b`.
One commit per package: D13 (stock lot, expiry, capacity, restock) then D14
(inventory filters, capacity display, bounded run-out forecast).

## Skill and document access

Read directly from the installed catalogue and repository (native skill loader
not required). All paths below were opened successfully unless marked otherwise.

- `/home/mike/.codex/skills/flutter-expert/SKILL.md`
- `/home/mike/.codex/skills/flutter-expert/references/riverpod-state.md`
- `/home/mike/.codex/skills/flutter-expert/references/widget-patterns.md`
- `/home/mike/.codex/skills/flutter-expert/references/gorouter-navigation.md`
- `/home/mike/.codex/skills/codebase-memory/SKILL.md`
- `/home/mike/.codex/skills/flutter-apply-architecture-best-practices/SKILL.md`
- `/home/mike/.codex/skills/dart-add-unit-test/SKILL.md`
- `/home/mike/.codex/skills/flutter-add-widget-test/SKILL.md`
- `/home/mike/.codex/skills/flutter-build-responsive-layout/SKILL.md`
- `/home/mike/.codex/skills/ui-ux-pro-max/SKILL.md`
- `/home/mike/.codex/skills/dart-run-static-analysis/SKILL.md`
- `/home/mike/.codex/skills/better-writing/SKILL.md`
- `/home/mike/.codex/skills/verification-before-completion/SKILL.md`
- `/home/mike/Development/true_grit_vital/.agents/skills/vital-mobile-copy/SKILL.md`
- `/home/mike/Development/true_grit_vital/AGENTS.md` (absent from this worktree)
- `/home/mike/Development/true_grit_vital/.scratch/vital-implementation/README.md`
- `/home/mike/Development/true_grit_vital/.scratch/vital-implementation/five-features-2026-10-22/D13-D14-stock.md`
- `/home/mike/Development/true_grit_vital/docs/specification/README.md`
- `/home/mike/Development/true_grit_vital/docs/specification/domain-and-record-integrity.md`
- `/home/mike/Development/true_grit_vital/docs/specification/content-and-interaction.md`
- `/home/mike/Development/true_grit_vital/docs/specification/privacy-security-and-safety.md`
- `/home/mike/Development/true_grit_vital/docs/discovery/engineering-skills-and-quality.md`
- `docs/design/roadmap.md`
- `docs/design/implementation-contract.md`
- `docs/design/components.md`
- `docs/design/interaction-blueprint.md`
- `docs/design/interaction-implementation-plan.md`

The `.scratch` and `docs/specification` trees exist only in the root checkout, so
those required documents were read there. No missing-file failure was hidden.

This note is extended during the work with graph coverage, test commands and
visual evidence.

## D13: lots, expiry and pack capacity

### What changed

- Container identity gains optional `lot`, civil `expiry_date`, and an exact
  positive `capacity` rational in the container unit. Schema 24 is additive;
  older rows read all three as null. `currentRecordSchemaVersion` moves to 24
  and drives backup/restore validation.
- `stock_container_metadata` keeps an immutable created/edited/migrated history.
  Metadata edits use the existing generation, owner and container revision
  guards plus the ordinary command/idempotency path.
- Capacity is descriptive only. Restocking may exceed it; the exact balance is
  never capped, and a known zero or deficit stays truthful.
- The canonical stock editor now has a `Details` mode using the same durable
  form, draft, lock and safe-exit engine. The initial container form groups the
  optional facts behind one disclosure.
- Restock help states that restocking keeps the old lot and strength; a new lot
  or strength is a new container, so old movement/strength snapshots stay
  unchanged.
- Structured JSON and CSV dose provenance gains the selected container's label,
  lot, expiry and exact capacity. JSON export schema moves to 2. Reports do not
  currently carry stock provenance, so no report fields were invented.
- A full encrypted backup/restore proves lot, expiry, capacity, metadata history
  and movement strength survive.

### Review fixes applied

- A create command with no metadata keeps the original ten-field payload shape,
  so frozen/idempotent receipts replay. Regression reads the stored identity.
- Details/quantity/notices keep distinct draft variants, route identities and
  task widget keys. A details draft never restores into a quantity editor.
- Capacity editing accepts an exact fraction such as `1/3` and prefills saved
  non-terminating values as a fraction, never rounded display text.
- Stock read/forecast providers are transaction-scoped and suspend during app
  lock; a lock cancels the in-flight stream without showing a false load error.
  Other failures keep their Retry path.

### Evidence

- `test/data/stock_metadata_store_test.dart`: blank defaults, exact capacity,
  rejected capacity/date, revision conflict/replay, unchanged movement
  snapshots, structured/CSV stock provenance and legacy payload identity.
- `test/data/stock_metadata_migration_test.dart`: schema 23 to 24, null defaults,
  migrated history and post-upgrade edit.
- `test/restore/stock_metadata_restore_test.dart`: real encrypted create,
  validate, prepare, activate and reopen with exact facts and history.
- `test/screen_stock_metadata_test.dart`: details save, dismissal guard, exact
  capacity across draft restore and separate draft identities.
- `test/screen_stock_inventory_test.dart`: updated stock copy/paging regression.
- Real-font light/dark and 320px 2x captures are committed under `captures/`
  from the final D14 pass; they include the D13 lot, expiry and capacity facts.

### Graph coverage

`check_index_coverage` on project `home-mike-Development-true_grit_vital`,
generation `2026-10-22T00:10:29Z`, returned `no_recorded_issue` for the existing
stock, export, draft, record and app paths. `lib/domain/stock/stock_forecast.dart`
was newly added after that index and is reported `missing`; its exact source was
read directly. Best-effort coverage is not proof of completeness.

### Limits

- Stock provenance is absent from PDF reports today; no stock-only report section
  was invented.
- Physical device accessibility, native boot and measured performance remain
  root/integration gates. This lane ran focused host tests only.

