#!/usr/bin/env python3
"""Run the Vital performance fixture against a device or the Linux host.

Every run is driven by one encoded job (`VITAL_PERF_JOB` dart-define). The
fixture measures, edits nothing outside its own storage and hands back one
self-labelling artifact that this tool validates with `validate.py`.
Numerical budgets never come from here: pass/fail exists only in
`compare.py` against a user-supplied budget file.

Modes:
  default             physical Android device over adb (profile build).
  --allow-emulator    permit an Android emulator as the target; artifacts stay
                      explicitly labelled `emulator` and never count towards
                      measured device evidence.
  --host-smoke        run the fixture on the Linux host (`host_smoke`),
      labelled; proves the harness plumbing, never device performance.

Exit codes: 0 measured and valid artifact, 1 invalid/failed, 2 tooling error.
Output is JSON on stdout.
"""
import json
import os
import hashlib
import platform as py_platform
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import validate  # noqa: E402

ROOT = HERE.parents[1]
FLUTTERW = ROOT / "tool/flutterw"
FIXTURE_TARGET = "integration_test/perf_fixture_test.dart"
DRIVER = "test_driver/perf_driver.dart"
PACKAGE = "dev.truegrit.vital"

SCENARIOS = validate.contract()["scenarioWorkloadKeys"]


def git_revision() -> str:
    return subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True, cwd=ROOT
    ).stdout.strip()


def flutter_versions() -> dict:
    out = subprocess.run(
        [str(FLUTTERW), "--version", "--machine"],
        capture_output=True, text=True, cwd=ROOT,
    )
    try:
        data = json.loads(out.stdout)
        return {
            "flutterSdkVersion": str(data.get("frameworkVersion", "")),
            "dartSdkVersion": str(data.get("dartSdkVersion", "")),
        }
    except json.JSONDecodeError:
        text = out.stdout or out.stderr
        raise SystemExit(json.dumps({"error": "flutter_version_unreadable",
                                     "detail": text[:400]}))


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fixture_source_revision() -> str:
    digest = hashlib.sha256()
    for path in sorted((ROOT / "integration_test/perf").glob("*.dart")) + [
        ROOT / "integration_test/perf_fixture_test.dart"
    ]:
        digest.update(path.name.encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def source_tree_revision() -> str:
    """Hash tracked and new runtime sources, including uncommitted changes.

    Git supplies the inventory, so ignored device configuration and credentials
    are excluded. Only runtime/fixture paths and pinned manifests are hashed.
    """
    inventory = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT
    ).decode().split("\0")
    prefixes = ("lib/", "assets/", "android/", "linux/", "third_party/", "integration_test/perf", "test_driver/", "tool/performance/")
    manifests = {"pubspec.yaml", "pubspec.lock", ".flutter-version"}
    digest = hashlib.sha256()
    for name in sorted(set(inventory)):
        if not name or not (name.startswith(prefixes) or name in manifests):
            continue
        path = ROOT / name
        if path.is_file():
            digest.update(name.encode())
            digest.update(b"\0")
            digest.update(path.read_bytes())
            digest.update(b"\0")
    return digest.hexdigest()


def adb_device(args: list[str], key: str) -> str | None:
    out = subprocess.run(["adb", "-s", *args, "shell", "getprop", key],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return None
    return out.stdout.strip()


class ToolingError(Exception):
    pass


def pick_device(requested: str | None, allow_emulator: bool) -> dict:
    listed = subprocess.run(["adb", "devices"], capture_output=True, text=True)
    if listed.returncode != 0:
        raise ToolingError("adb_unavailable")
    serials = [
        line.split("\t")[0]
        for line in listed.stdout.splitlines()[1:]
        if line.endswith("\tdevice") and line.split("\t")[0].strip()
    ]
    if requested:
        if requested not in serials:
            raise ToolingError(f"device_not_connected:{requested}")
        serial = requested
    elif len(serials) == 1:
        serial = serials[0]
    elif not serials:
        raise ToolingError("no_device_connected")
    else:
        raise ToolingError("ambiguous_devices")

    facts = {
        key: adb_device([serial], key)
        for key in (
            "ro.product.model", "ro.product.manufacturer",
            "ro.build.version.release", "ro.build.version.sdk",
            "ro.boot.qemu", "ro.kernel.qemu",
        )
    }
    is_emulator = facts.get("ro.boot.qemu") == "1" or facts.get("ro.kernel.qemu") == "1"
    if not is_emulator:
        # Fallback on the fingerprint when qemu props are absent.
        fingerprint = adb_device([serial], "ro.build.fingerprint") or ""
        is_emulator = "generic" in fingerprint or "emulator" in fingerprint
    if is_emulator and not allow_emulator:
        raise ToolingError(
            "emulator_refused -- the target is an emulator; measure.py only "
            "runs it with --allow-emulator and its artifacts stay labelled "
            "emulator, never measured device evidence"
        )
    return {
        "id": serial,
        "model": facts["ro.product.model"],
        "manufacturer": facts["ro.product.manufacturer"],
        "osRelease": facts["ro.build.version.release"],
        "osSdk": facts["ro.build.version.sdk"],
        "isEmulator": bool(is_emulator),
    }


def run(command: list[str], log: Path, artifact_path: Path) -> int:
    with log.open("w") as handle:
        return subprocess.run(
            command, cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT,
            timeout=3600, env={**os.environ, "VITAL_PERF_ARTIFACT_PATH": str(artifact_path.resolve())},
        ).returncode


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--id", help="adb serial; defaults to the only device")
    parser.add_argument("--scenarios", nargs="*", choices=SCENARIOS,
                        default=list(SCENARIOS))
    parser.add_argument("--repeats", type=int, default=12)
    parser.add_argument("--volume", choices=("standard", "wider"),
                        default="standard")
    parser.add_argument("--glass", action="store_true",
                        help="exercise the glass surface in fixture-only mode")
    parser.add_argument("--reduce-motion", action="store_true")
    parser.add_argument("--text-scale", type=float, default=None)
    parser.add_argument("--allow-emulator", action="store_true")
    parser.add_argument("--host-smoke", action="store_true")
    parser.add_argument("--out", type=Path, default=ROOT / "build/performance")
    parser.add_argument("--evidence-dir", type=Path, default=None)
    args = parser.parse_args()

    if args.text_scale is not None and not 0.5 <= args.text_scale <= 4.0:
        raise SystemExit(json.dumps({"error": "text_scale_out_of_range"}))

    try:
        versions = flutter_versions()
    except SystemExit as error:
        print(error, file=sys.stderr)
        return 2

    host = {
        "gitRevision": git_revision(),
        **versions,
        "pubspecLockSha256": sha256_file(ROOT / "pubspec.lock"),
        "fixtureSourceRevision": fixture_source_revision(),
        "sourceTreeSha256": source_tree_revision(),
    }

    if args.host_smoke:
        device = {
            "id": f"linux-{py_platform.machine()}",
            "model": None,
            "manufacturer": "host",
            "osRelease": py_platform.release(),
            "osSdk": None,
            "isEmulator": False,
        }
        device_class, evidence_class, build_mode = "host", "host_smoke", "host_smoke"
        device_facts: dict = {}
        command_position: list[str] = []
    else:
        try:
            device = pick_device(args.id, args.allow_emulator)
        except ToolingError as error:
            print(json.dumps({"error": str(error)}))
            return 2
        device_class = "emulator" if device["isEmulator"] else "physical"
        evidence_class = "emulator" if device["isEmulator"] else "physical_device"
        build_mode = "profile"
        device_facts = {
            "model": device["model"],
            "manufacturer": device["manufacturer"],
            "osRelease": device["osRelease"],
            "osSdk": device["osSdk"],
        }
        command_position = ["--profile", "-d", device["id"]]

    run_id = "vital-perf-{}-{}".format(
        time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()), device["id"]
    ).replace("/", "-")

    out_dir = args.out / run_id
    out_dir.mkdir(parents=True, exist_ok=True)
    artifact_path = out_dir / "artifact.json"
    job = {
        "runId": run_id,
        "evidenceClass": evidence_class,
        "deviceClass": device_class,
        "deviceId": device["id"],
        "deviceFacts": device_facts,
        "host": host,
        "scenarios": list(args.scenarios),
        "repeats": args.repeats,
        "volume": args.volume,
        "glass": bool(args.glass),
        "reduceMotion": bool(args.reduce_motion),
        "textScale": args.text_scale,
        "hostOut": str(artifact_path) if args.host_smoke else None,
    }
    (out_dir / "job.json").write_text(json.dumps(job, indent=2, sort_keys=True))

    command = [str(FLUTTERW)]
    if args.host_smoke:
        command += ["test", "--no-pub", FIXTURE_TARGET, "-d", "linux",
                    "--dart-define=VITAL_PERF_JOB=" + json.dumps(job, sort_keys=True),
                    "--dart-define=VITAL_PERF_HOST_OUT=" + str(artifact_path)]
    else:
        command += ["drive", *command_position,
                    "--driver", DRIVER, "--target", FIXTURE_TARGET,
                    "--no-pub",
                    "--dart-define=VITAL_PERF_JOB=" + json.dumps(job, sort_keys=True)]

    exit_code = run(command, out_dir / "run.log", artifact_path)
    if exit_code != 0:
        print(json.dumps({
            "error": "fixture_failed", "exitCode": exit_code,
            "job": job, "runId": run_id, "log": str(out_dir / "run.log"),
        }, indent=2))
        return 1
    if not artifact_path.exists():
        print(json.dumps({
            "error": "artifact_not_written", "job": job, "runId": run_id,
            "log": str(out_dir / "run.log"),
        }, indent=2))
        return 1

    artifact = json.loads(artifact_path.read_text())
    verdict = validate.validate(artifact, source=str(artifact_path))
    (out_dir / "verdict.json").write_text(json.dumps(verdict, indent=2))
    if verdict["status"] != "valid":
        print(json.dumps({
            "error": "artifact_invalid", "runId": run_id, "verdict": verdict,
        }, indent=2))
        return 1

    unsupported = [s["key"] for s in artifact["scenarios"] if s["status"] != "measured"]
    report = {"status": "incomplete" if unsupported else evidence_class, "unsupportedScenarios": unsupported, "runId": run_id, "verdict": verdict,
              "job": job, "artifact": str(artifact_path)}
    if args.evidence_dir:
        evidence = Path(args.evidence_dir)
        evidence.mkdir(parents=True, exist_ok=True)
        for name in ("artifact.json", "verdict.json", "job.json", "run.log"):
            (evidence / name).write_bytes((out_dir / name).read_bytes())
        report["evidenceDir"] = str(evidence)
    print(json.dumps(report, indent=2))
    return 1 if unsupported else 0


if __name__ == "__main__":
    raise SystemExit(main())
