#!/usr/bin/env python3
"""Deterministic self-test for the Vital performance tooling.

The self-test never touches a device or the app: it builds synthetic
artifacts in-process, validates them with the same contract logic as real
runs and mutates the positive case into negative cases that must each fail
with a specific violation. It also performs the cross-language drift check:
the constants the Python tooling relies on are re-parsed from the Dart
sources, so a one-sided contract edit fails the self-test instead of
validating a stale copy at some later date.

By default the evidence report is written to the R02 review directory
(docs/design/reviews/2026-10-23-roadmap-finish/R02/selftest.json); the path
can be overridden with --evidence.

Exit codes: 0 all cases and drift checks pass, 1 any failure, 2 tooling
error. Output is JSON on stdout.
"""
import argparse
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import validate  # noqa: E402

ROOT = HERE.parents[1]
JOB_DART = ROOT / "integration_test/perf/job.dart"

SELFTEST_RUN_ID = "vital-perf-selftest-00000001"
SELFTEST_CREATED_UTC = "2026-10-23T00:00:00Z"


def _dart_string(source: str, name: str) -> str:
    match = re.search(r"const " + re.escape(name) + r" =\s*'([^']*)';", source)
    if not match:
        raise SystemExit(json.dumps({"error": f"missing_dart_constant:{name}"}))
    return match.group(1)


def dart_constants() -> dict:
    job = JOB_DART.read_text()
    return {
        "fixtureSpec": _dart_string(job, "perfFixtureSpec"),
        "toolVersion": _dart_string(job, "perfHarnessToolVersion"),
        "kind": _dart_string(job, "perfArtifactKind"),
        "schemaVersion": validate._dart_int(job, "perfArtifactSchemaVersion"),
        "defaultSeed": validate._dart_int(job, "perfDefaultSeed"),
    }


def synthetic_frames(budget: int = 16667) -> dict:
    """Deterministic, closed-form frame arrays with their recomputed summary.

    Some build times exceed the declared budget so the jank counters are
    non-trivial; the summary numbers are the same recomputation the validator
    performs, so the positive artifact passes by construction. The scenario
    declares a 60 Hz budget (16667 µs) and the arrays keep every sample far
    from that boundary, so a reproducible pass is stable across the budget
    and threshold rounding.
    """
    build = [8000 + (i * 97) % 7000 for i in range(48)]
    for i in range(0, 48, 9):
        build[i] += 17000
    raster = [3000 + (i * 53) % 4000 for i in range(48)]
    frames = validate.derive_sdk_summary(build, raster, budget)
    frames.update({
        # Layer/picture cache counts and memory are VM-side facts that are
        # type-checked (not recomputable from the raw arrays); every frame
        # carries at most one cached layer and picture in this model.
        "average_layer_cache_count": 2,
        "90th_percentile_layer_cache_count": 3,
        "99th_percentile_layer_cache_count": 4,
        "worst_layer_cache_count": 5,
        "average_layer_cache_memory": 1.0,
        "90th_percentile_layer_cache_memory": 2.0,
        "99th_percentile_layer_cache_memory": 2.0,
        "worst_layer_cache_memory": 3.0,
        "average_picture_cache_count": 1,
        "90th_percentile_picture_cache_count": 1,
        "99th_percentile_picture_cache_count": 2,
        "worst_picture_cache_count": 2,
        "average_picture_cache_memory": 0.5,
        "90th_percentile_picture_cache_memory": 0.5,
        "99th_percentile_picture_cache_memory": 1.0,
        "worst_picture_cache_memory": 1.0,
        "new_gen_gc_count": 7,
        "old_gen_gc_count": 3,
    })
    keys = validate.contract()["frameSummaryKeys"]
    missing = [key for key in keys if key not in frames]
    if missing:
        raise SystemExit(json.dumps({
            "error": "selftest_frame_summary_gap", "missing": missing,
        }))
    return {key: frames[key] for key in keys}


def synthetic_scenario(measured: bool) -> dict:
    scenario_keys = validate.contract()["scenarioKeys"]
    keys = validate.contract()["scenarioWorkloadKeys"]
    base = {
        "key": keys[0],
        "status": "measured" if measured else "unsupported",
        "reason": None,
        "repeats": 12,
        "refreshRateHz": 60.0,
        "refreshRateKnown": True,
        "frameBudgetMicros": 16667,
        "memoryBeforeKb": 102400,
        "memoryAfterKb": 103424,
        "frames": synthetic_frames() if measured else None,
    }
    if not measured:
        base.update({
            "key": keys[-1],
            "repeats": 0,
            "refreshRateHz": None,
            "refreshRateKnown": False,
            "frameBudgetMicros": None,
            "memoryBeforeKb": None,
            "memoryAfterKb": None,
            "reason": "selftest_unsupported_case",
        })
    return {key: base[key] for key in scenario_keys}


def synthetic_artifact() -> dict:
    constants = dart_constants()
    survey = [synthetic_scenario(True), synthetic_scenario(False)]
    detail = {
        "schemaVersion": constants["schemaVersion"],
        "kind": constants["kind"],
        "role": "selftest",
        "toolVersion": constants["toolVersion"],
        "runId": SELFTEST_RUN_ID,
        "createdUtc": SELFTEST_CREATED_UTC,
        "evidenceClass": "selftest",
        "buildMode": "host_smoke",
        "host": {
            "gitRevision": "selftest", "flutterSdkVersion": "selftest",
            "dartSdkVersion": "selftest", "pubspecLockSha256": "selftest",
            "fixtureSourceRevision": "selftest", "sourceTreeSha256": "selftest",
        },
        "device": {
            "deviceClass": "host", "id": "selftest-host", "model": None,
            "manufacturer": "selftest", "osRelease": "selftest",
            "osSdk": None, "isEmulator": False,
        },
        "conditions": {
            "refreshRateHz": None,
            "refreshRateKnown": False,
            "textScaleSystem": 1.0,
            "appearanceOpaquePreference": False,
            "appearanceReduceMotion": False,
            "systemReduceAnimations": False,
            "systemHighContrast": False,
        },
        "glass": {
            "requested": False,
            "fixtureOnly": True,
            "productionGateProviderValue": False,
            "disclosure": "Synthetic selftest disclosure longer than the "
                          "minimum required by the artifact contract, so the "
                          "glass fields exercise type and length checks.",
        },
        "fixtureIdentity": {
            "spec": constants["fixtureSpec"],
            "seed": constants["defaultSeed"],
            "dataset": {"items": 6, "records": 480, "containers": 36},
            "datasetHash": "selftest-dataset-hash",
            "storeGeneration": "selftest-generation",
        },
        "scenarios": survey,
        "limitations": [
            "Selftest artifact generated in-process by "
            "tool/performance/selftest.py; no device was touched.",
        ],
    }
    return detail


def _set_unsupported_reasonless(artifact: dict) -> None:
    section = next(
        s for s in artifact["scenarios"] if s["status"] == "unsupported"
    )
    section["reason"] = None


NEGATIVE_CASES: tuple[tuple[str, callable, str], ...] = (
    (
        "glass_gate_forgery",
        lambda a: a["glass"].__setitem__("productionGateProviderValue", True),
        "glass_gate_forgery",
    ),
    (
        "frames_count_mismatch",
        lambda a: a["scenarios"][0]["frames"].__setitem__(
            "frame_count", a["scenarios"][0]["frames"]["frame_count"] + 1
        ),
        "frames_count_mismatch:today_swipe",
    ),
    (
        "role_evidence_mismatch",
        lambda a: a.__setitem__("role", "measured"),
        "role_evidence_mismatch:measured/selftest",
    ),
    ("unsupported_missing_reason", _set_unsupported_reasonless,
     "unsupported_missing_reason:record_save"),
    (
        "frames_stats_mismatch",
        lambda a: a["scenarios"][0]["frames"].__setitem__(
            "90th_percentile_frame_build_time_millis",
            a["scenarios"][0]["frames"]
            ["90th_percentile_frame_build_time_millis"] + 0.5,
        ),
        "frames_stats_mismatch:today_swipe",
    ),
    ("keys_mismatch", lambda a: a.__setitem__("extraKey", 1), "keys_mismatch"),
    (
        "scenario_key_unknown",
        lambda a: a["scenarios"][0].__setitem__("key", "why_not"),
        "scenario_key_unknown:why_not",
    ),
    (
        "emulator_role_measured",
        lambda a: (
            a["device"].__setitem__("deviceClass", "emulator"),
            a.__setitem__("role", "measured"),
        ),
        "emulator_role_measured",
    ),
    (
        "created_utc_bad",
        lambda a: a.__setitem__("createdUtc", "not-a-time"),
        "created_utc",
    ),
)


def run_cases() -> list[dict]:
    good = synthetic_artifact()
    results: list[dict] = []

    first = validate.validate(json.loads(json.dumps(good)), "positive")
    first_without_source = dict(first, source=None)
    repeat = dict(
        validate.validate(json.loads(json.dumps(good)), "positive-repeat"),
        source=None,
    )
    results.append({
        "case": "positive_deterministic",
        "status": "pass" if first["status"] == "valid" else "fail",
        "expected": "valid",
        "violations": first["violations"],
    } | ({"verdict": first} if first["status"] != "valid" else {}))
    results.append({
        "case": "repeat_determinism",
        "status": "pass" if first_without_source == repeat else "fail",
    })

    for name, mutate, expected_violation in NEGATIVE_CASES:
        artifact = json.loads(json.dumps(good))
        mutate(artifact)
        verdict = validate.validate(artifact, name)
        passed = (
            verdict["status"] == "invalid"
            and expected_violation in verdict["violations"]
        )
        results.append({
            "case": name,
            "status": "pass" if passed else "fail",
            "expected": expected_violation,
            "violations": verdict["violations"],
        })
    return results


def drift_checks() -> list[dict]:
    results = []
    contract = validate.contract()
    dart = dart_constants()

    def check(name: str, ok: bool, detail: dict | None = None) -> None:
        entry = {"case": f"drift_{name}", "status": "pass" if ok else "fail"}
        if detail is not None:
            entry.update(detail)
        results.append(entry)

    check("tool_version_constant", dart["toolVersion"] == validate.TOOL_VERSION,
          {"dart": dart["toolVersion"], "python": validate.TOOL_VERSION})
    check("fixture_spec_constant", dart["fixtureSpec"] == validate.FIXTURE_SPEC,
          {"dart": dart["fixtureSpec"], "python": validate.FIXTURE_SPEC})
    check("artifact_kind_constant", dart["kind"] == validate.ARTIFACT_KIND,
          {"dart": dart["kind"], "python": validate.ARTIFACT_KIND})
    check(
        "schema_version_constant",
        dart["schemaVersion"] == contract["artifactSchemaVersion"],
        {"dart": dart["schemaVersion"], "python": contract["artifactSchemaVersion"]},
    )
    scenario_keys = contract["scenarioWorkloadKeys"]
    check(
        "scenario_registry_shape",
        len(scenario_keys) == 4 and "today_swipe" in scenario_keys,
        {"scenarios": scenario_keys},
    )
    check(
        "roles_match_evidence_map",
        sorted(set(contract["roleRequirement"].values()))
        == sorted(contract["roles"]),
    )
    check(
        "evidence_classes_complete",
        sorted(contract["evidenceClasses"])
        == sorted(contract["roleRequirement"].keys()),
    )
    check(
        "frames_summary_contains_raw_arrays",
        {"frame_count", "frame_build_times", "frame_rasterizer_times",
         "new_gen_gc_count", "old_gen_gc_count"}.issubset(
             set(contract["frameSummaryKeys"])),
    )
    check(
        "scenario_sections_use_contract_keys",
        all(sorted(section.keys()) == sorted(contract["scenarioKeys"])
            for section in synthetic_artifact()["scenarios"]),
        {"scenarioKeys": contract["scenarioKeys"]},
    )
    check(
        "top_keys_used_by_selftest",
        set(synthetic_artifact().keys()) == set(contract["topKeys"]),
    )
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--evidence",
        type=Path,
        default=ROOT / ("docs/design/reviews/2026-10-23-roadmap-finish/"
                        "R02/selftest.json"),
    )
    args = parser.parse_args()

    results = run_cases() + drift_checks()
    failed = [entry for entry in results if entry["status"] != "pass"]
    report = {
        "tool": "vital-perf-selftest/1",
        "status": "pass" if not failed else "fail",
        "artifactsValidated": len(
            [entry for entry in results if not entry["case"].startswith("drift")]
        ),
        "driftChecks": len(
            [entry for entry in results if entry["case"].startswith("drift")]
        ),
        "results": results,
        "failures": failed,
    }
    if args.evidence:
        args.evidence.parent.mkdir(parents=True, exist_ok=True)
        args.evidence.write_text(json.dumps(report, indent=2, sort_keys=True))
        report["evidence"] = str(args.evidence)
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
