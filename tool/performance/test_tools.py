"""Host checks for failure paths that must never produce budget passes."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import selftest
import validate


class BudgetChecks(unittest.TestCase):
    def compare(self, candidate, budgets=None):
        with tempfile.TemporaryDirectory(prefix="vital-perf-tools-") as folder:
            root = Path(folder)
            baseline = root / "baseline.json"
            baseline.write_text(json.dumps(selftest.synthetic_artifact()))
            target = root / "candidate.json"
            target.write_text(json.dumps(candidate))
            command = [sys.executable, str(Path(__file__).with_name("compare.py")), str(baseline), str(target)]
            if budgets is not None:
                budget = root / "budgets.json"
                budget.write_text(json.dumps({"scenarios": budgets}))
                command.extend(["--budgets", str(budget)])
            result = subprocess.run(command, capture_output=True, text=True)
            return result.returncode, json.loads(result.stdout or result.stderr)

    def test_sdk_percentiles_sort_chronological_frame_arrays(self):
        summary = validate.derive_sdk_summary([9000, 1000, 5000], [6000, 1000, 2000], 16667)
        self.assertEqual(summary['90th_percentile_frame_build_time_millis'], 9.0)
        self.assertEqual(summary['99th_percentile_frame_rasterizer_time_millis'], 6.0)

    def test_unmeasured_budget_scenario_fails(self):
        code, report = self.compare(selftest.synthetic_artifact(), {"record_save": {"buildMaxMs": 999}})
        self.assertNotEqual(code, 0)
        self.assertEqual(report["failures"][0]["reason"], "candidate_not_measured")

    def test_nan_and_invalid_budget_types_fail(self):
        for value in [float("nan"), float("inf"), -1, True, "fast"]:
            with self.subTest(value=value):
                code, report = self.compare(selftest.synthetic_artifact(), {"today_swipe": {"buildMaxMs": value}})
                self.assertNotEqual(code, 0)
                self.assertEqual(report["error"], "budget_limit_invalid")

    def test_changed_conditions_cannot_claim_budget_pass(self):
        candidate = selftest.synthetic_artifact()
        candidate["conditions"]["textScaleSystem"] = 2.0
        code, report = self.compare(candidate, {"today_swipe": {"buildMaxMs": 999}})
        self.assertNotEqual(code, 0)
        self.assertEqual(report["error"], "incomparable_budget_runs")

    def test_unbudgeted_comparison_never_claims_device_acceptance(self):
        code, report = self.compare(selftest.synthetic_artifact())
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "unbudgeted")
        self.assertFalse(report["deviceAcceptance"])
        self.assertEqual(report["evidenceClass"], "selftest")


if __name__ == "__main__":
    unittest.main()
