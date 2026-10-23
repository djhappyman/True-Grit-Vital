# Timing and follow-ups

The canonical schedule editor now offers two independent, optional choices:
a user-defined timing window and one follow-up delay. Both start off; there
are no clinical defaults. Exact settings travel with immutable plan/expectation
snapshots. History labels compare known captured planned and reported actual
instants, without judging dose safety. Date-only, unknown and voided entries
receive no label.

Follow-ups use the existing reminder reconciliation and native opaque-token
pipeline. Taken/Skip cancel both requests; explicit Snooze replaces them.
Follow-ups cannot displace primary alerts or reserved snoozes. Delivered or
possibly delivered receipts stay terminal through config changes and cancellation
acknowledgements, including a late native posted receipt. Plan-end/pause and
existing owner, revision, dataset and clock guards remain authoritative.
Restoring a backup intentionally resets native reminder requests and delivery
receipts, as it did before this change; this is not a cross-restore delivery ledger.

Host evidence: 256 scheduling/store/reconciler checks; 32 existing reminder UI,
alert, stock-alert and plan-instruction checks; 25 timing UI/domain/allocation
checks, then 12 follow-up store checks including immutable history after an edit
and encrypted restart. Whole-project analysis passes. Focused passing logs and
corrected earlier runs are retained in the local batch tracker. The 320px/2x
light/dark captures use bundled fonts and real shared controls; the editor
captures cover reduced motion. Canonical Preview/Save and invalid-input checks
cover durable saved settings and stale-preview clearing.

No schema or dependency upgrade. Physical Android delivery, OS scheduling
behaviour and device accessibility/performance acceptance remain open.
Loaded skill sources: `/home/mike/.codex/skills/flutter-expert/SKILL.md`,
`codebase-memory/SKILL.md`, `dart-add-unit-test/SKILL.md`,
`flutter-apply-architecture-best-practices/SKILL.md`,
`verification-before-completion/SKILL.md`, `better-writing/SKILL.md` and the
repository `.agents/skills/vital-mobile-copy/SKILL.md`; shared interaction
blueprint and engineering policy were applied.
