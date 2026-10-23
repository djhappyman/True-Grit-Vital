# Performance evidence

The free GLM lane stopped with unfinished work. The lead recovered it, fixed the
fixture and evidence pipeline, and verified the integrated tooling.

The opt-in harness uses the pinned SDK's actual frame timings, an isolated
encrypted synthetic dataset, four real interaction workloads and explicit
physical-device/emulator/host labels. Source, SDK, dataset, conditions and
refresh-rate facts travel with every artifact. Validation recomputes statistics
from raw frame arrays. Comparisons grant a numerical pass only against an
explicit user-supplied budget and matching conditions; no budgets are adopted.
Production glass remains disabled. Glass-on is a fixture-only option.

## Verification

- 21 Dart fixture/job/artifact checks passed.
- Five Python failure-path checks passed; deterministic contract self-tests
  validate 11 artifacts and ten drift cases (`selftest.json`).
- A real Linux host run completed Today paging, History and stock scrolling,
  and repeated dose Save/Undo. `artifact.json`, `job.json`, `verdict.json` and
  `run.log` retain the result and captured source-tree hash. These belong to
  that exact working-tree snapshot, not a claim of a clean release commit.
- The artifact validates as `host_smoke`, with no unsupported workloads.
  Its timings describe this host. They establish neither target-device
  performance nor acceptable glass rendering.

Run commands, dataset bounds and the artifact contract are in
[the harness guide](../../../../../tool/performance/README.md).
No physical Android device or owner-adopted numerical budgets were available;
D24/G06 remain open. Detailed passing logs and corrected failing runs are kept
in the local batch tracker.
