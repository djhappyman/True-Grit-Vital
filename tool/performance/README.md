# Vital performance harness (tool/performance)

A repeatable, bounded, opt-in measurement harness for True Grit Vital. It is
built on the pinned SDK's official `IntegrationTestWidgetsFlutterBinding
.watchPerformance` API (no Flutter driver dependency) and backed by a
deterministic synthetic dataset created inside a fixture-only storage
directory.

The harness records facts; it never invents them. Numerical budgets are
never bundled with the tool — comparisons pass or fail only against files
the user supplies explicitly.

## Files

| File | Purpose |
| --- | --- |
| `measure.py` | Runs the fixture on a physical device (or `--host-smoke` on Linux) and validates the produced artifact. |
| `validate.py` | Deterministic artifact validator; recomputes the pinned SDK summarizer statistics from the raw frame arrays. |
| `compare.py` | Delta table between two validated artifacts; optional pass/fail only against a user-supplied budget file. |
| `selftest.py` | Deterministic in-process self-test of the validator plus the cross-language contract drift check; writes the R02 evidence JSON. |
| `README.md` | This document. |

The supporting fixture code lives in `integration_test/perf/`
(`job.dart`, `environment.dart`, `dataset.dart`, `scenarios.dart`,
`artifact.dart`) with `integration_test/perf_fixture_test.dart` as the
entry point and `test_driver/perf_driver.dart` as the device-side handoff.

## The Python/Dart contract link

`validate.py` does not hard-code the artifact key lists. It parses them
from the Dart constants (`perfArtifactTopLevelKeys`,
`perfScenarioKeys`, `perfFrameSummaryKeys`, …) at run time, so tool and
fixture cannot drift silently; `selftest.py` additionally re-checks the
simple string constants (tool version, fixture spec, kind, schema version)
against `integration_test/perf/job.dart` and `tool/performance/validate.py`.
A one-sided contract edit fails the self-test immediately.

The recomputation of summarizer statistics matches the pinned SDK
exactly: integer average (`sum ~/ n`, then `/1e3`), the percentile index
rule `((n-1)*p).round()` (Dart rounds half away from zero, which is what
`sdk_percentile_index` implements), sorted-index worst values and strict
`>` jank counting against the mutable `kBuildBudget`.

## Running

There is no numerical target and no device is required to develop the
harness. Three evidence classes exist and every run declares its own:

* `physical_device` — profile-mode run on a real Android device (`measured`).
* `emulator` — Android emulator; refused unless `--allow-emulator` and
  never counted as device evidence.
* `host_smoke` — the fixture run on the Linux host, self-labeled, never
  device evidence.

```bash
# Hardware run (profile build, real device):
tool/performance/measure.py --id <adb-serial> [--scenarios today_swipe ...] \
  [--repeats 12] [--volume standard|wider] [--glass] [--reduce-motion] \
  [--text-scale 1.2] [--evidence-dir PATH]

# Linux host smoke (proves plumbing, labelled host_smoke):
tool/performance/measure.py --host-smoke

# Validate an artifact:
tool/performance/validate.py build/performance/<runId>/artifact.json

# Compare two valid artifacts (unbudgeted table):
tool/performance/compare.py BASELINE CANDIDATE

# Apply user-supplied budgets (never bundled):
tool/performance/compare.py BASELINE CANDIDATE --budgets budgets.json

# In-process self-test + drift check, writes the evidence JSON:
tool/performance/selftest.py [--evidence PATH]
```

Artifacts and logs land in `build/performance/<runId>/`
(`artifact.json`, `verdict.json`, `job.json`, `run.log`). `--evidence-dir`
also mirrors them for review records.

## Measurement scenarios

| Key | Route | Landmark | Work |
| --- | --- | --- | --- |
| `today_swipe` | `/today` | `Today` | Repeated balanced horizontal drags across the shell pager (off Today and back). |
| `history_scroll` | `/history` | `History` | Repeated balanced vertical drags over the central scrollable. |
| `stock_scroll` | `/stock/me` | `Stock` | Repeated balanced vertical drags over the stock list. |
| `record_save` | `/record/<itemId>` | the dose form field | One navigation, one real save and one Undo per repeat. |

`--glass` only composes the glass surface in the fixture: it overrides
`glassEnabledProvider` inside the run's own ProviderScope. Production glass
is now enabled by owner direction; physical validation remains separate.
The artifact's `glass` block says exactly that (`fixtureOnly: true`,
`productionDeviceValidated: false` plus the fixed disclosure string).

## What the artifact records

One JSON file per run, canonicalised with recursively sorted keys so
equal inputs give byte-identical output. Blocks:

* `role`, `evidenceClass`, `buildMode`, `runId`, `createdUtc` — the self-
  labelling core. `physical_device ⇒ measured`; `host_smoke ⇒ host_smoke`.
  Nothing measured on a non-device run can masquerade as device evidence.
* `host` — git revision, pinned Flutter/Dart SDK versions, sha256 of
  `pubspec.lock` and of the perf fixture sources.
* `device` — class, id, model/manufacturer/os facts from `adb getprop`
  (`null` when the platform does not report one).
* `conditions` — display refresh rate (`refreshRateKnown` honest), system
  text scale, appearance preferences actually written into the store, and
  system reduce-animations/high-contrast flags.
* `glass` — as above.
* `fixtureIdentity` — spec, seed, dataset counts, deterministic dataset
  hash, store generation.
* `scenarios` — per-scenario status (`measured` or truthfully
  `unsupported` with a reason), repeats, per-scenario refresh/budget,
  process memory kb before/after and the raw `FrameTimingSummarizer` map
  (including per-frame arrays, GC counts and layer/picture cache fields).
* `limitations` — free-text honesty, e.g. what a host smoke run cannot say.

## Budget files (opt-in, user-supplied)

```
{
  "scenarios": {
    "today_swipe": { "buildP95Ms": 12.0, "jankShareMax": 0.05 }
  }
}
```

Every scenario entry is a dict of metric constraints. Supported metric
names, all compared against the *candidate*:

`buildAverageMs`, `buildP50Ms`, `buildP95Ms`, `buildP99Ms`, `buildMaxMs`,
`rasterAverageMs`, `rasterP50Ms`, `rasterP95Ms`, `rasterP99Ms`,
`rasterMaxMs`, `jankShareMax` (max of build/raster jank share),
`frameCountMax`, `memoryGrowthKbMax`.

Unknown metric or scenario keys fail closed (exit 2). Missing scenarios
carry no constraint. A pass/fail verdict exists only with `--budgets`.

## Safety boundaries (non-negotiable)

* The fixture never touches production storage: its own encrypted dataset
  is created in a fixture directory it reports (`/data/user/0/
  dev.truegrit.vital/cache/…` attempts on Android, an explicit directory
  on the host) and deleted afterwards (`VITAL_PERF_KEEP_FIXTURE` keeps it
  on failure). Native `prepare`/`activate` are never called.
* No live health data, no real names: the synthetic dataset is deterministic
  (seed `20261023`, fixed command ids, dataset hash in the artifact).
* The fixture refuses to run without the harness job dart-define, so it
  can never enter ordinary `tool/verify` sessions by accident
  (`tool/verify` runs `test/` only; `integration_test/` is not bulk-run).
* The harness never edits shared files, gate statuses, obligations, or
  the production appearance provider.
* No approved numerical budgets exist yet. Any comparison claim must name
  the user-supplied budget file it used.

## Known limitations (2026-10-23, R02)

* No physical Android device is currently attached, so no device evidence
  (`physical_device`) exists yet; the harness, host smoke runs and the
  self-test are delivered in this state.
* Glass-on composition is exercised in fixture mode; the visual review of
  the composed glass render path on a target device is still open and
  stays open until a human looks at it.
* `flutter drive` on device uses the pinned SDK's default DDS setup; no
  `--no-dds` flag exists in Flutter 3.47.7.
* Emulator artifacts are structurally supported but refused by default;
  they must be labelled `emulator` and never treated as measured device
  evidence.

## Lead verification refinements

Runtime sources, including uncommitted tracked and new files, receive a separate
`sourceTreeSha256`; the Git revision alone is not a claim that the working tree
was clean. Dataset dates use a fixed UTC epoch. The historical
`textScaleSystem` field reports the effective test dispatcher scale, including
an explicit `--text-scale` override. History uses the full list view.

Unsupported workloads make the measurement command exit nonzero. Budgeted
scenarios must actually be measured. Non-finite, negative and non-numeric
budgets are rejected, and device/dataset/SDK/condition differences prevent a
budget pass. Glass-on versus opaque remains an intentional permitted experiment.
Unbudgeted comparisons disclose differences and never grant device acceptance.
Run `python3 tool/performance/test_tools.py` for these failure-path checks.

Artifact schema/tool version 2 separates the enabled visual treatment from
physical-device acceptance. Earlier version 1 artifacts remain dated evidence
in their review folders and must not be compared as current-contract runs.
