# Fifteen-task review

23 October 2026. Fourteen implementation/hardening tasks plus one acceptance
audit, continuing from `cdefb2a`. Three Sol 6.1 workers completed their assigned
changes. The two free OpenCode DeepSeek lanes hit their limit and switched to
paid OpenCode. OpenCode event streams then disconnected across the DeepSeek
lanes; the lead recovered checkpoints, finished the work and verified integration.
No failed worker was counted as a completed implementation on its own.

| Task | Finished result |
| --- | --- |
| T01 | Independent isolate-owned backup snapshot connections and bounded cleanup |
| T02 | Captured authority for protected-file actions, rollback and safe handoff |
| T03 | Strict report dates, safe defaults and guarded report replacement |
| T04 | Debounced/cancellable catalogue search using the shared input |
| T05 | Edit exact dose presets with guarded saves and retained failed edits |
| T06 | Reviewable 30d, 90d and Year export ranges in the verified display zone |
| T07 | Exact lab source revision and nested return context from trend tables |
| T08 | Whole-ledger stock movement filters before paging |
| T09 | Factual pack-detail revision differences and reachable boundary rows |
| T10 | Watched saved injection-site history with canonical source inspection |
| T11 | Exact seven-day plan totals, separate units and explicit incomplete cases |
| T12 | Strict quick-entry dates, explicit task choices and retained context |
| T13 | Dataset/lock/route-bound deletion with transaction rollback guards |
| T14 | Separate pending/unconfirmed reminder-cancellation facts and details |
| T15 | Evidence-based original-plan and roadmap audit |

Individual folders contain captures and scope notes. Images use synthetic records,
bundled app fonts and real shared Flutter components. Tests exercise both themes,
narrow/large text and relevant keyboard, dismissal, lock and state preservation.
These are host checks, not TalkBack or physical-device/performance acceptance.

## Verification

Focused feature checks were run during integration; the final source passes
whole-project analysis. Later integration reruns cover export, privacy, quick
entry, stock movement/source links, metadata history/drafts and store regressions.
The final native Linux boot uses the real Secret Service, an isolated encrypted
dataset, durable recording, navigation and reviewed export. Its machine-readable
[result](native-result.json) records cleanup and exit status. Detailed commands,
passing logs and corrected failing runs remain in the local batch tracker under
`.scratch/vital-implementation/fifteen-2026-10-22/verification/`.

No dependency/schema upgrade, clinical defaults, catalogue corpus admission,
automatic-backup policy, signed artifact or release-gate closure is included.

## What remains

- D11: structured food/bedtime requirements and an agreed timing-tolerance model;
  D19's on-time/late display depends on that model.
- D12: opt-in follow-up policy and physical notification evidence.
- D15: scanning source/licence/privacy and ambiguous-pack handling. Native
  low-stock notices already have host implementation; device delivery is open.
- D21: automatic protected backups need destination, retention, key and lifecycle
  decisions. Manual encrypted backup/restore and receipts already exist.
- D22: choose exact FHIR/HL7 version and mappings. JSON/CSV exports are not FHIR.
- D24: glass stays gated until representative-device measurements pass.
- Today observations deliberately remain a Coming soon preview; the existing
  detailed observation editor remains available elsewhere.
- Original plan: admitted catalogue terms/corpus (G05), physical Android delivery,
  transfer/key recovery, interruption/storage-pressure and accessibility evidence,
  adopted performance budgets, populated migration checks and hosted CI, then
  owner signing/publisher/privacy decisions, pilot and production distribution.

The [dated acceptance audit](T15/acceptance-audit.md) distinguishes original
28-step host capabilities from open gates. Its saved-inventory counts are a
baseline, not a new completion percentage. Step 03 is superseded by single-user
scope. Linux boot success and the earlier debug prerelease do not close Android
pilot/public-release or later-platform gates.
