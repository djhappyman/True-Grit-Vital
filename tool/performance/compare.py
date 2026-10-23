#!/usr/bin/env python3
"""Compare measured Vital performance artifacts and apply optional budgets.

Usage:
    compare.py BASELINE CANDIDATE [--budgets FILE]

Both inputs must be artifacts that `validate.py` accepts; they are validated
again here so a corrupted file can never produce a comparison table.

Comparisons run on the raw frame-time arrays, not on the summarized fields,
so candidate and baseline do not need identical frame counts. Scenario jank
shares are recomputed from the raw arrays against each scenario's declared
frame budget.

Budgets never come bundled with the tool. `--budgets` points at a
user-supplied JSON file whose schema is documented in
`tool/performance/README.md`; unknown metric or scenario keys fail closed
(exit 2). Without `--budgets` the tool prints the delta table only.

Exit codes: 0 (all supplied budgets met), 1 (budget exceeded or invalid
inputs), 2 (tooling error). Output is JSON on stdout.
"""
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import validate  # noqa: E402

# Metric names a budget file may constrain. Documented in the README; every
# name maps to a number in one scenario entry of the budget file.
METRIC_KEYS = (
    "buildAverageMs", "buildP50Ms", "buildP95Ms", "buildP99Ms", "buildMaxMs",
    "rasterAverageMs", "rasterP50Ms", "rasterP95Ms", "rasterP99Ms",
    "rasterMaxMs", "jankShareMax", "frameCountMax", "memoryGrowthKbMax",
)


def load_artifact(path: Path, descriptor: str) -> dict:
    try:
        artifact = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(json.dumps({"error": f"unreadable:{descriptor}",
                                     "detail": str(error)}))
    verdict = validate.validate(artifact, source=str(path))
    if verdict["status"] != "valid":
        raise SystemExit(json.dumps({
            "error": f"invalid_artifact:{descriptor}", "verdict": verdict,
        }))
    return artifact


def scenario_metrics(section: dict) -> dict:
    build = section["frames"]["frame_build_times"]
    raster = section["frames"]["frame_rasterizer_times"]
    budget = section.get("frameBudgetMicros")
    budget = budget if isinstance(budget, int) else 16000
    stats = validate.derive_frame_stats(build, raster)
    return {
        "frameCount": len(build),
        "build": stats["build"],
        "raster": stats["raster"],
        "jankShareBuild": (
            sum(1 for value in build if value > budget) / len(build)
            if build else 0.0
        ),
        "jankShareRaster": (
            sum(1 for value in raster if value > budget) / len(raster)
            if raster else 0.0
        ),
        "frameBudgetMicros": budget,
        "memoryBeforeKb": section.get("memoryBeforeKb"),
        "memoryAfterKb": section.get("memoryAfterKb"),
        "memoryGrowthKb": (
            section["memoryAfterKb"] - section["memoryBeforeKb"]
            if isinstance(section.get("memoryAfterKb"), int)
            and isinstance(section.get("memoryBeforeKb"), int)
            else None
        ),
    }


def measured_scenarios(artifact: dict, descriptor: str) -> dict:
    return {
        section["key"]: section
        for section in artifact["scenarios"]
        if section["status"] == "measured"
    } if artifact.get("scenarios") else {}


def _value_for(metrics: dict, metric: str):
    if metric == "jankShareMax":
        return max(metrics["jankShareBuild"], metrics["jankShareRaster"])
    if metric == "frameCountMax":
        return metrics["frameCount"]
    if metric == "memoryGrowthKbMax":
        return metrics["memoryGrowthKb"]
    # buildP95Ms / rasterMaxMs / buildAverageMs style names.
    if metric.startswith("build"):
        return metrics["build"].get(
            {"AverageMs": "averageMs", "P50Ms": "p50Ms", "P95Ms": "p95Ms",
             "P99Ms": "p99Ms", "MaxMs": "maxMs"}[metric.removeprefix("build")])
    if metric.startswith("raster"):
        return metrics["raster"].get(
            {"AverageMs": "averageMs", "P50Ms": "p50Ms", "P95Ms": "p95Ms",
             "P99Ms": "p99Ms", "MaxMs": "maxMs"}[metric.removeprefix("raster")])
    raise SystemExit(json.dumps({"error": f"unknown_metric:{metric}"}))


def budget_entries(path: Path) -> dict:
    try:
        budgets = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(json.dumps({"error": "budgets_unreadable",
                                     "detail": str(error)}))
    if not isinstance(budgets, dict) or set(budgets) - {"scenarios"}:
        raise SystemExit(json.dumps({"error": "budgets_schema"}))
    scenarios = budgets.get("scenarios", {})
    if not isinstance(scenarios, dict):
        raise SystemExit(json.dumps({"error": "budgets_schema"}))
    allowed = set(validate.contract()["scenarioWorkloadKeys"])
    unknown = sorted(set(scenarios) - allowed)
    if unknown:
        raise SystemExit(json.dumps({"error": "unknown_budget_scenario",
                                     "scenarios": unknown}))
    for key, constraints in scenarios.items():
        if not isinstance(constraints, dict):
            raise SystemExit(json.dumps({"error": "budget_constraints_not_object", "scenario": key}))
        for metric, limit in constraints.items():
            if isinstance(limit, bool) or not isinstance(limit, (int, float)) or not math.isfinite(limit) or limit < 0:
                raise SystemExit(json.dumps({"error": "budget_limit_invalid", "scenario": key, "metric": metric}))
        bad = sorted(set(constraints) - set(METRIC_KEYS))
        if bad:
            raise SystemExit(json.dumps({
                "error": "unknown_budget_metric", "scenario": key,
                "metrics": bad, "supported": list(METRIC_KEYS),
            }))
    return scenarios


def comparison_differences(baseline: dict, candidate: dict) -> list[str]:
    """Budget checks require the same device, dataset, SDK and conditions.

    Glass requested is deliberately excluded: comparing opaque against the
    fixture glass path is the experiment. All results still need human review.
    """
    fields = ["evidenceClass", "buildMode", "device", "conditions"]
    differences = [key for key in fields if baseline[key] != candidate[key]]
    for key in ("datasetHash", "spec", "seed", "dataset"):
        if baseline["fixtureIdentity"][key] != candidate["fixtureIdentity"][key]:
            differences.append("fixtureIdentity." + key)
    for key in ("flutterSdkVersion", "dartSdkVersion", "fixtureSourceRevision"):
        if baseline["host"][key] != candidate["host"][key]:
            differences.append("host." + key)
    return differences


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--budgets", type=Path, default=None,
                        help="user-supplied budget file; required for "
                             "pass/fail, never bundled")
    args = parser.parse_args()

    if not validate.contract()["scenarioWorkloadKeys"]:
        raise SystemExit(json.dumps({"error": "contract_unavailable"}))

    baseline = load_artifact(args.baseline, "baseline")
    candidate = load_artifact(args.candidate, "candidate")

    table: list[dict] = []
    failures: list[dict] = []
    budgets = budget_entries(args.budgets) if args.budgets else {}
    reviewed_keys = sorted(
        set(measured_scenarios(baseline, "baseline"))
        | set(measured_scenarios(candidate, "candidate")) | set(budgets)
    )
    differences = comparison_differences(baseline, candidate)
    if differences and budgets:
        raise SystemExit(json.dumps({"error": "incomparable_budget_runs", "differences": differences}))

    for key in reviewed_keys:
        row: dict = {"key": key}
        for descriptor, artifact in (
            ("baseline", baseline), ("candidate", candidate)
        ):
            section = measured_scenarios(artifact, descriptor).get(key)
            if section is not None:
                row[descriptor] = scenario_metrics(section)
            else:
                row[descriptor] = None
        if row["baseline"] is not None and row["candidate"] is not None:
            row["delta"] = {
                "frameCount": row["candidate"]["frameCount"]
                - row["baseline"]["frameCount"],
                "jankShareBuild": row["candidate"]["jankShareBuild"]
                - row["baseline"]["jankShareBuild"],
                "jankShareRaster": row["candidate"]["jankShareRaster"]
                - row["baseline"]["jankShareRaster"],
            }
            if row["candidate"]["build"]["p95Ms"] is not None:
                row["delta"]["buildP95Ms"] = (
                    row["candidate"]["build"]["p95Ms"]
                    - row["baseline"]["build"]["p95Ms"]
                )
            if row["candidate"]["raster"]["p95Ms"] is not None:
                row["delta"]["rasterP95Ms"] = (
                    row["candidate"]["raster"]["p95Ms"]
                    - row["baseline"]["raster"]["p95Ms"]
                )

        budget = budgets.get(key)
        if budget:
            row["budget"] = budget
            if row["candidate"] is None:
                failures.append({"key": key, "reason": "candidate_not_measured"})
            else:
                for metric, limit in budget.items():
                    value = _value_for(row["candidate"], metric)
                    if value is None:
                        failures.append({"key": key, "metric": metric,
                                         "reason": "metric_unavailable"})
                    elif value > limit:
                        failures.append({
                            "key": key, "metric": metric,
                            "value": value, "limit": limit,
                        })
        table.append(row)

    result = {
        "status": "fail" if failures else ("pass" if budgets else "unbudgeted"),
        "baseline": str(args.baseline),
        "candidate": str(args.candidate),
        "budgets": str(args.budgets) if args.budgets else None,
        "failures": failures,
        "comparisonDifferences": differences,
        "evidenceClass": candidate["evidenceClass"],
        "deviceAcceptance": False,
        "scenarios": table,
    }
    print(json.dumps(result, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
