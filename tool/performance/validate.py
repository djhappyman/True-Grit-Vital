#!/usr/bin/env python3
"""Deterministic validator for Vital performance artifacts.

The contract is defined in `integration_test/perf/artifact.dart` and
`integration_test/perf/job.dart`; this validator mirrors those key lists by
parsing the constants out of the Dart sources so tool and fixture cannot
drift silently. It recomputes the pinned SDK summarizer statistics from the
raw frame arrays and fails closed on every violation.

Exit codes: 0 valid, 1 invalid, 2 tooling error. Output is JSON on stdout.
"""
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ARTIFACT_DART = ROOT / "integration_test/perf/artifact.dart"
JOB_DART = ROOT / "integration_test/perf/job.dart"

TOOL_VERSION = "vital-perf-harness/1"
FIXTURE_SPEC = "vital-perf-fixture/1"
ARTIFACT_KIND = "vital-performance-artifact"


def _dart_string_list(source: str, name: str) -> list[str]:
    match = re.search(
        r"const " + re.escape(name) + r" =\s*\[(\s*'[^']*'\s*,?\s*)+\];", source
    )
    if not match:
        raise SystemExit(f"missing Dart constant: {name}")
    return re.findall(r"'([^']*)'", match.group(0))


def _dart_string_key_map(source: str, name: str) -> dict[str, str]:
    match = re.search(r"const " + re.escape(name) + r" =\s*\{(.*?)\};", source, re.S)
    if not match:
        raise SystemExit(f"missing Dart constant: {name}")
    return dict(
        (found.group(1), found.group(2))
        for found in re.finditer(r"'([^']+)':\s*'([^']+)'", match.group(1))
    )


def _dart_int(source: str, name: str) -> int:
    match = re.search(r"const " + re.escape(name) + r" = (\d+);", source)
    if not match:
        raise SystemExit(f"missing Dart constant: {name}")
    return int(match.group(1))


def load_dart_contract() -> dict:
    artifact = ARTIFACT_DART.read_text()
    job = JOB_DART.read_text()
    return {
        "topKeys": _dart_string_list(artifact, "perfArtifactTopLevelKeys"),
        "scenarioKeys": _dart_string_list(artifact, "perfArtifactScenarioKeys"),
        "frameSummaryKeys": _dart_string_list(artifact, "perfFrameSummaryKeys"),
        "roles": _dart_string_list(artifact, "perfArtifactRoles"),
        "roleRequirement": _dart_string_key_map(
            artifact, "perfEvidenceRoleRequirement"
        ),
        "hostKeys": _dart_string_list(artifact, "perfArtifactHostKeys"),
        "deviceKeys": _dart_string_list(artifact, "perfArtifactDeviceKeys"),
        "conditionKeys": _dart_string_list(artifact, "perfArtifactConditionKeys"),
        "glassKeys": _dart_string_list(artifact, "perfArtifactGlassKeys"),
        "identityKeys": _dart_string_list(
            artifact, "perfArtifactFixtureIdentityKeys"
        ),
        "datasetKeys": _dart_string_list(artifact, "perfArtifactDatasetKeys"),
        "scenarioWorkloadKeys": _dart_string_list(job, "perfScenarioKeys"),
        "statuses": _dart_string_list(job, "perfScenarioStatuses"),
        "deviceClasses": _dart_string_list(job, "perfDeviceClasses"),
        "evidenceClasses": _dart_string_list(job, "perfEvidenceClasses"),
        "buildModes": _dart_string_list(job, "perfBuildModes"),
        "artifactSchemaVersion": _dart_int(job, "perfArtifactSchemaVersion"),
    }


_CONTRACT: dict | None = None


def contract() -> dict:
    global _CONTRACT
    if _CONTRACT is None:
        _CONTRACT = load_dart_contract()
    return _CONTRACT


# SDK percentile rule: nearest index with round-half-away-from-zero, matching
# Dart's `num.round()` exactly while Python's `round()` rounds half to even.
def sdk_percentile_index(length: int, p: float) -> int:
    return math.floor((length - 1) * p + 0.5)


def count_exceed(data: list[int], threshold: int) -> int:
    return sum(1 for value in data if value > threshold)


def derive_sdk_summary(
    build_times: list[int], raster_times: list[int], budget: int
) -> dict:
    """Recomputation of the pinned SDK `FrameTimingSummarizer.summary` shape."""
    total = len(build_times)

    def average_us(times: list[int]) -> float:
        return (sum(times) // total) / 1e3 if total else 0.0

    def percentile_ms(times: list[int], p: float) -> float:
        index = sdk_percentile_index(total, p)
        return sorted(times)[index] / 1e3

    return {
        "average_frame_build_time_millis": average_us(build_times),
        "90th_percentile_frame_build_time_millis": percentile_ms(build_times, 0.90),
        "99th_percentile_frame_build_time_millis": percentile_ms(build_times, 0.99),
        "worst_frame_build_time_millis": max(build_times) / 1e3,
        "missed_frame_build_budget_count": count_exceed(build_times, budget),
        "average_frame_rasterizer_time_millis": average_us(raster_times),
        "90th_percentile_frame_rasterizer_time_millis": percentile_ms(
            raster_times, 0.90
        ),
        "99th_percentile_frame_rasterizer_time_millis": percentile_ms(
            raster_times, 0.99
        ),
        "worst_frame_rasterizer_time_millis": max(raster_times) / 1e3,
        "missed_frame_rasterizer_budget_count": count_exceed(raster_times, budget),
        "frame_count": total,
        "frame_build_times": list(build_times),
        "frame_rasterizer_times": list(raster_times),
        "new_gen_gc_count": None,
        "old_gen_gc_count": None,
        "layer_and_picture_cache_fields": "not_recomputed",
    }


def derive_frame_stats(build_times: list[int], raster_times: list[int]) -> dict:
    """Fixture-agnostic derived statistics for comparison output."""
    total = len(build_times)
    return {
        "frame_count": total,
        "build": _distribution(build_times),
        "raster": _distribution(raster_times),
    }


def _distribution(values: list[int]) -> dict:
    ordered = sorted(values)
    total = len(ordered)
    return {
        "p50Ms": ordered[sdk_percentile_index(total, 0.50)] / 1e3 if total else None,
        "p95Ms": ordered[sdk_percentile_index(total, 0.95)] / 1e3 if total else None,
        "p99Ms": ordered[sdk_percentile_index(total, 0.99)] / 1e3 if total else None,
        "maxMs": ordered[-1] / 1e3 if total else None,
        "averageMs": (sum(ordered) / total) / 1e3 if total else None,
    }


def validate(artifact: dict, source: str | None = None) -> dict:
    """Validates one parsed artifact and returns a JSON-safe verdict."""
    violations: list[str] = []

    def bad(code: str) -> None:
        if code not in violations:
            violations.append(code)

    if not isinstance(artifact, dict):
        return {"status": "invalid", "violations": ["artifact_not_object"]}

    c = contract()
    if sorted(artifact.keys()) != sorted(c["topKeys"]):
        bad("keys_mismatch")
        return {"status": "invalid", "violations": violations}

    if artifact["schemaVersion"] != c["artifactSchemaVersion"]:
        bad("schema_version")
    if artifact["toolVersion"] != TOOL_VERSION:
        bad("tool_version")
    if artifact["kind"] != ARTIFACT_KIND:
        bad("kind")

    role, evidence = artifact["role"], artifact["evidenceClass"]
    if evidence not in c["evidenceClasses"]:
        bad(f"bad_evidence_class:{evidence}")
        return {"status": "invalid", "violations": violations}
    if role != c["roleRequirement"].get(evidence):
        bad(f"role_evidence_mismatch:{role}/{evidence}")

    run_id = artifact.get("runId")
    if not isinstance(run_id, str) or not (1 <= len(run_id) <= 128):
        bad("run_id")
    created = artifact.get("createdUtc")
    if not isinstance(created, str) or not re.fullmatch(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z?", created or ""
    ):
        bad("created_utc")
    if artifact.get("buildMode") not in c["buildModes"]:
        bad("build_mode")

    device = _block(artifact, "device", c["deviceKeys"], bad)
    device_class = None
    if isinstance(device, dict) and device:
        device_class = device.get("deviceClass")
        if device_class not in c["deviceClasses"]:
            bad("device_class")
        if device_class == "physical" and device.get("isEmulator") is True:
            bad("device_class_emulator_contradiction")
        if device_class == "emulator" and role == "measured":
            bad("emulator_role_measured")
        for key in ("id", "model", "manufacturer", "osRelease", "osSdk"):
            value = device.get(key)
            if value is not None and not isinstance(value, str):
                bad(f"device_type:{key}")
        if device.get("isEmulator") is not None and not isinstance(
            device["isEmulator"], bool
        ):
            bad("device_isEmulator_type")

    conditions = _block(artifact, "conditions", c["conditionKeys"], bad)
    refresh = conditions.get("refreshRateHz") if isinstance(conditions, dict) else None
    known = conditions.get("refreshRateKnown") if isinstance(conditions, dict) else None
    if not isinstance(known, bool):
        bad("conditions_refreshKnown_type")
    elif known is True:
        if not isinstance(refresh, (int, float)) or not (20 <= refresh <= 500):
            bad("conditions_refresh_rate")
    elif refresh is not None:
        bad("conditions_refresh_rate_unknown_surplus")
    if isinstance(conditions, dict):
        scale = conditions.get("textScaleSystem")
        if scale is not None and not (isinstance(scale, (int, float)) and 0.2 <= scale <= 5):
            bad("conditions_text_scale")
        for key in ("appearanceOpaquePreference", "appearanceReduceMotion"):
            if not isinstance(conditions.get(key), bool):
                bad(f"conditions_{key}_type")
        for key in ("systemReduceAnimations", "systemHighContrast"):
            value = conditions.get(key)
            if value is not None and not isinstance(value, bool):
                bad(f"conditions_{key}_type")

    glass = _block(artifact, "glass", c["glassKeys"], bad)
    if isinstance(glass, dict) and glass:
        if glass.get("productionGateProviderValue") is not False:
            bad("glass_gate_forgery")
        if glass.get("fixtureOnly") is not True:
            bad("glass_gate_forgery")
        if not isinstance(glass.get("requested"), bool):
            bad("glass_requested_type")
        disclosure = glass.get("disclosure")
        if not isinstance(disclosure, str) or len(disclosure) < 40:
            bad("glass_disclosure")

    host = _block(artifact, "host", c["hostKeys"], bad)
    if isinstance(host, dict) and host:
        for key in c["hostKeys"]:
            value = host.get(key)
            if not isinstance(value, str) or not value:
                bad(f"host_missing:{key}")

    identity = _block(
        artifact, "fixtureIdentity", c["identityKeys"], bad
    )
    dataset = None
    if isinstance(identity, dict) and identity:
        if identity.get("spec") != FIXTURE_SPEC:
            bad("fixture_spec")
        if not isinstance(identity.get("seed"), int) or identity["seed"] < 0:
            bad("fixture_seed")
        dataset = identity.get("dataset")
        if not isinstance(dataset, dict) or sorted(dataset.keys()) != sorted(
            c["datasetKeys"]
        ):
            bad("fixture_identity_dataset_mismatch")
            dataset = None
        else:
            for key, raw in dataset.items():
                if not isinstance(raw, int) or raw < 0:
                    bad(f"fixture_identity_bad_count:{key}")
        if not isinstance(identity.get("datasetHash"), str) or not identity["datasetHash"]:
            bad("fixture_hash")
        if not isinstance(identity.get("storeGeneration"), str) or not identity[
            "storeGeneration"
        ]:
            bad("fixture_store_generation")

    scenarios = artifact.get("scenarios")
    if not isinstance(scenarios, list) or not scenarios:
        bad("scenarios_missing")
        scenarios = []

    seen: set[str] = set()
    scenario_summary: list[dict] = []
    for section in scenarios:
        if not isinstance(section, dict):
            bad("scenario_not_object")
            continue
        key, status = section.get("key"), section.get("status")
        if key not in c["scenarioWorkloadKeys"] or key in seen:
            bad(f"scenario_key_unknown:{key}")
            continue
        seen.add(key)
        if sorted(section.keys()) != sorted(c["scenarioKeys"]):
            bad(f"scenario_keys_mismatch:{key}")
            continue
        if status not in c["statuses"]:
            bad(f"scenario_status_invalid:{key}")
            continue
        repeats = section.get("repeats")
        if not isinstance(repeats, int) or repeats < 0:
            bad(f"scenario_repeats_type:{key}")
        for field in ("memoryBeforeKb", "memoryAfterKb"):
            value = section.get(field)
            if value is not None and not (isinstance(value, int) and value >= 0):
                bad(f"memory_type:{key}")
        entry: dict = {"key": key, "status": status}
        if status == "unsupported":
            reason = section.get("reason")
            if not isinstance(reason, str) or not reason:
                bad(f"unsupported_missing_reason:{key}")
            elif len(reason) > 500:
                bad(f"reason_too_long:{key}")
            if section.get("frames") is not None:
                bad(f"unsupported_frames_present:{key}")
        else:
            frames = section.get("frames")
            if not isinstance(frames, dict) or sorted(frames.keys()) != sorted(
                c["frameSummaryKeys"]
            ):
                bad(f"frames_shape:{key}")
                scenario_summary.append(entry)
                continue
            build_times = frames.get("frame_build_times")
            raster_times = frames.get("frame_rasterizer_times")
            if not (
                isinstance(build_times, list)
                and isinstance(raster_times, list)
                and all(isinstance(v, int) and v >= 0 for v in build_times)
                and all(isinstance(v, int) and v >= 0 for v in raster_times)
            ):
                bad(f"frames_arrays_invalid:{key}")
                scenario_summary.append(entry)
                continue
            if frames.get("frame_count") != len(build_times) or len(
                build_times
            ) != len(raster_times):
                bad(f"frames_count_mismatch:{key}")
                entry["frameCount"] = (
                    frames.get("frame_count")
                    if isinstance(frames.get("frame_count"), int)
                    else 0
                )
                scenario_summary.append(entry)
                continue
            budget = section.get("frameBudgetMicros")
            budget = budget if isinstance(budget, int) else 16000
            expected = derive_sdk_summary(build_times, raster_times, budget)
            if not _sdk_summary_matches(frames, expected, c["frameSummaryKeys"]):
                bad(f"frames_stats_mismatch:{key}")
            refresh_value = section.get("refreshRateHz")
            if isinstance(refresh_value, (int, float)) and refresh_value > 0:
                implied = 1e6 / refresh_value
                if abs(implied - budget) / implied > 0.05:
                    bad(f"refresh_budget_mismatch:{key}")
            entry["frameCount"] = len(build_times)
            entry["budgetMicros"] = budget
            entry["build"] = _distribution(build_times)
            entry["jankShare"] = count_exceed(build_times, budget) / len(build_times)
        scenario_summary.append(entry)

    limitations = artifact.get("limitations")
    if not isinstance(limitations, list) or not all(
        isinstance(item, str) and item for item in limitations
    ):
        bad("limitations")

    verdict = {
        "status": "valid" if not violations else "invalid",
        "violations": violations,
        "runId": run_id if isinstance(run_id, str) else None,
        "role": role,
        "evidenceClass": evidence,
        "scenarios": scenario_summary,
    }
    if source:
        verdict["source"] = source
    return verdict


def _block(artifact: dict, name: str, keys: list[str], bad) -> dict | None:
    block = artifact.get(name)
    if not isinstance(block, dict) or sorted(block.keys()) != sorted(keys):
        bad(f"block_keys_mismatch:{name}")
        return None
    return block


def _sdk_summary_matches(
    actual: dict, expected: dict, frame_keys: list[str]
) -> bool:
    for key in frame_keys:
        if key in ("new_gen_gc_count", "old_gen_gc_count"):
            # GC counts come from VM timeline events; recorded by the fixture
            # through the summarizer, so they are present but not recomputable
            # from arrays. Only type-check them.
            value = actual.get(key)
            if value is not None and not isinstance(value, int):
                return False
            continue
        if key in (
            "average_layer_cache_count",
            "90th_percentile_layer_cache_count",
            "99th_percentile_layer_cache_count",
            "worst_layer_cache_count",
            "average_layer_cache_memory",
            "90th_percentile_layer_cache_memory",
            "99th_percentile_layer_cache_memory",
            "worst_layer_cache_memory",
            "average_picture_cache_count",
            "90th_percentile_picture_cache_count",
            "99th_percentile_picture_cache_count",
            "worst_picture_cache_count",
            "average_picture_cache_memory",
            "90th_percentile_picture_cache_memory",
            "99th_percentile_picture_cache_memory",
            "worst_picture_cache_memory",
        ):
            value = actual.get(key)
            if value is not None and not isinstance(value, (int, float)):
                return False
            continue
        observed = actual.get(key)
        expected_value = expected[key]
        if expected_value is None:
            continue
        if isinstance(expected_value, float):
            if not isinstance(observed, (int, float)) or not math.isclose(
                observed, expected_value, rel_tol=1e-9, abs_tol=1e-9
            ):
                return False
        elif observed != expected_value:
            return False
    return True


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    args = parser.parse_args()
    try:
        artifact = json.loads(args.artifact.read_text())
    except (OSError, json.JSONDecodeError) as error:
        print(
            json.dumps({"status": "invalid", "violations": [f"unreadable:{error}"]})
        )
        return 1
    result = validate(artifact, source=str(args.artifact))
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "valid" else 1


if __name__ == "__main__":
    raise SystemExit(main())
