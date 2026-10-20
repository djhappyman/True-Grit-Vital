#!/usr/bin/env python3
"""Record the reproducible True Grit: Vital boot matrix.

Every row starts unverified. A row becomes ``passed`` only after its command
actually ran in this invocation. Physical and publisher evidence cannot be
synthesised here: those rows stay open for the owner/lead.

Usage:
    python3 tool/release/boot_matrix.py [--run-host] [--devices] [--strict]

Exit status: 0 for an honest recorded matrix, 1 when an executed boot check
failed (or, with --strict, when a required row is not passed).
"""

from __future__ import annotations

import argparse
import datetime
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "build/release-boot-matrix.json"


def row(
    row_id: str,
    host: str,
    command: str,
    status: str,
    note: str,
    **extra: object,
) -> dict[str, object]:
    return {
        "id": row_id,
        "host": host,
        "command": command,
        "status": status,
        "note": note,
        "executed": False,
        **extra,
    }


def run_host_boot() -> dict[str, object]:
    command = [str(ROOT / "tool/flutterw"), "test", "--no-pub", "test/release/boot_smoke_test.dart"]
    process = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    output = (process.stdout + process.stderr).strip().splitlines()
    passed = process.returncode == 0 and any("All tests passed" in line for line in output)
    item = row(
        "host-widget-boot",
        "Flutter host (Linux workstation)",
        "./tool/flutterw test --no-pub test/release/boot_smoke_test.dart",
        "passed" if passed else "failed",
        "Boots the real app shell against isolated synthetic SQLite storage.",
        executed=True,
    )
    item["exitCode"] = process.returncode
    item["evidence"] = output[-8:]
    return item


def run_linux_boot() -> dict[str, object]:
    command = ['python3', str(ROOT / 'tool/release/run_linux_boot.py')]
    process = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    item = row('linux-native-boot', 'Linux desktop',
               'python3 tool/release/run_linux_boot.py',
               'passed' if process.returncode == 0 else 'failed',
               'Real encrypted SQLite, isolated Secret Service key, native UI, reopen and export preview.',
               executed=True)
    item['exitCode'] = process.returncode
    item['evidence'] = 'build/linux-native-boot/result.json'
    return item


def devices() -> tuple[list[str], str]:
    try:
        process = subprocess.run(
            [str(ROOT / "tool/flutterw"), "devices", "--machine"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return [], f"device discovery failed: {error}"
    if process.returncode != 0:
        return [], f"device discovery failed: {process.stderr.strip() or process.stdout.strip()}"
    try:
        payload = json.loads(process.stdout)
    except json.JSONDecodeError as error:
        return [], f"device discovery returned non-JSON output: {error}"
    return [entry.get("id", "unknown") for entry in payload], "device discovery succeeded"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-host", action="store_true", help="Run the host widget boot fixture.")
    parser.add_argument('--run-linux', action='store_true', help='Run isolated native Linux boot with real Secret Service.')
    parser.add_argument("--devices", action="store_true", help="Record currently connected Flutter devices.")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail unless every required boot row was executed and passed.",
    )
    args = parser.parse_args(argv)

    rows = [
        (
            run_host_boot()
            if args.run_host
            else row(
                "host-widget-boot",
                "Flutter host (Linux workstation)",
                "./tool/flutterw test --no-pub test/release/boot_smoke_test.dart",
                "not-run",
                "Host widget boot is automated but has not run in this invocation.",
            )
        ),
        run_linux_boot() if args.run_linux else row(
            "linux-native-boot",
            "Linux desktop",
            "python3 tool/release/run_linux_boot.py",
            "not-run",
            "Needs a graphical session and unlocked Secret Service keyring. "
            "Preserve any failed-launch recovery evidence; do not infer a pass from a process start.",
        ),
        row(
            "linux-packaged-bundle",
            "Linux packaged release",
            "./tool/package_linux.sh && output/linux/true-grit-vital/launch",
            "not-run",
            "Packaging and release-mode launch are lead/owner actions, not part of this worker run.",
        ),
        row(
            "android-emulator-boot",
            "Dedicated Android emulator",
            "./tool/flutterw devices then ./tool/flutterw run -d <emulator-id>",
            "not-run",
            "Use a disposable synthetic AVD only. Record the device id, API level and host-run evidence.",
        ),
        row(
            "android-physical-pilot",
            "Physical Android pilot device",
            "G06 reference-device matrix",
            "unavailable",
            "No physical device is connected. TalkBack, large text, notification replay, "
            "reboot/force-stop/OEM and measured performance remain open (G06).",
        ),
        row(
            "chrome-web-boot",
            "Chrome/web",
            "not adopted",
            "unsupported",
            "Web storage, durability, key and notification contracts are not implemented.",
        ),
    ]

    device_ids: list[str] = []
    device_note = "device discovery not requested"
    if args.devices:
        device_ids, device_note = devices()

    for item in rows:
        if item["id"] in {"android-emulator-boot", "android-physical-pilot"}:
            item["devices"] = device_ids
            item["note"] = f"{item['note']} {device_note}."

    failed = [item["id"] for item in rows if item["status"] == "failed"]
    required = [item for item in rows if item["status"] != "unsupported"]
    unverified = [item["id"] for item in required if item["status"] != "passed"]

    report = {
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "baseCommit": "da0ec27692a42130d606eb1003a529c0aa1df6b5",
        "rows": rows,
        "failed": failed,
        "unverifiedRequiredRows": unverified,
        "releaseBootReady": False,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    for item in rows:
        print(f"{item['status'].upper():11} {item['id']}: {item['note']}")
    print(f"REPORT {REPORT}")
    print("RESULT release-boot-ready=false; physical/packaged evidence remains open")

    if failed:
        return 1
    if args.strict and unverified:
        print("STRICT: unverified required rows: " + ", ".join(unverified))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
