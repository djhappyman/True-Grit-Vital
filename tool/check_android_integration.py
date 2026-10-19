#!/usr/bin/env python3
"""Run integration fixtures on a dedicated AVD and restore its whole snapshot.

Flutter integration installation may replace app data. A complete emulator
snapshot preserves the encrypted database and Android Keystore together.
Never use this harness on a physical device or for credential-changing tests.
"""
import argparse
import hashlib
import json
import os
import re
import selectors
import signal
import sys
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "dev.truegrit.vital"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="+")
    parser.add_argument("--device", default="emulator-5556")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--grant-reminders", action="store_true",
                        help="Grant notification/exact-alarm capabilities inside the restored synthetic AVD snapshot")
    parser.add_argument("--drive-reminder-action", action="store_true",
                        help="Deliver the isolated fixture's synthetic action twice through its Android Activity")
    args = parser.parse_args()
    if args.drive_reminder_action and (not args.grant_reminders or (len(args.tests) != 1 or args.tests[0] not in {"integration_test/reminders_native_test.dart", "integration_test/reminder_flow_test.dart"})):
        parser.error("Action driving is only for one approved reminder fixture with reminder grants")
    if not args.device.startswith("emulator-"):
        parser.error("Only a dedicated emulator is permitted")
    for name in args.tests:
        path = (ROOT / name).resolve()
        if path.parent != ROOT / "integration_test" or not path.name.endswith("_test.dart") or not path.is_file():
            parser.error("Tests must be existing direct integration_test/*_test.dart files")
        if path.name == "app_auth_native_test.dart":
            parser.error("Credential tests require check_android_auth.py")

    def adb(*words, timeout=60):
        return subprocess.run(["adb", "-s", args.device, *words], check=True,
                              capture_output=True, text=True, timeout=timeout).stdout

    if adb("shell", "getprop", "ro.kernel.qemu").strip() != "1":
        raise RuntimeError("Target is not a verified emulator")
    if adb("emu", "avd", "name").splitlines()[0].strip() != "vital_api36":
        raise RuntimeError("Target is not Vital's dedicated synthetic AVD")
    adb("shell", "am", "force-stop", PACKAGE)

    def hashes():
        return adb("shell", "run-as", PACKAGE, "sha256sum",
                   "no_backup/vital/records.sqlite", "no_backup/vital/key-envelope.json")

    def reminder_hash():
        result = subprocess.run(["adb", "-s", args.device, "shell", "run-as", PACKAGE,
                                 "sha256sum", "no_backup/reminders-v1/journal.enc"],
                                capture_output=True, text=True, timeout=60)
        if result.returncode == 0:
            return result.stdout.strip()
        if "No such file" in result.stderr or "No such file" in result.stdout:
            return "absent"
        raise RuntimeError("Could not inspect protected reminder journal")

    original = hashes()
    original_reminder = reminder_hash()
    snapshot = f"vital-integration-{time.time_ns()}"
    if "OK" not in adb("emu", "avd", "snapshot", "save", snapshot, timeout=120):
        raise RuntimeError("Could not preserve AVD data and Keystore")
    evidence = {"device": args.device, "snapshot": snapshot, "tests": [], "passed": False}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        if args.grant_reminders:
            # The permission must already be declared by the installed normal
            # reminder build. Never grant before the complete snapshot exists.
            adb("shell", "pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS")
            adb("shell", "appops", "set", PACKAGE, "SCHEDULE_EXACT_ALARM", "allow")
            evidence["synthetic_reminder_capabilities_granted"] = True
        for name in args.tests:
            command = [str(ROOT / "tool/flutterw"), "test", "--no-pub", "--reporter", "expanded",
                       "-d", args.device, name]
            if not args.drive_reminder_action:
                code = subprocess.run(command, cwd=ROOT, timeout=600).returncode
            else:
                # Only opaque synthetic tokens are accepted. This verifies the
                # actual Activity intent boundary, not a notification-shade tap.
                child = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                                         stderr=subprocess.STDOUT, start_new_session=True)
                selector = selectors.DefaultSelector()
                selector.register(child.stdout, selectors.EVENT_READ)
                buffer = b""
                deadline = time.monotonic() + 600
                driven = False
                try:
                    while selector.get_map():
                        if time.monotonic() >= deadline:
                            raise TimeoutError("Reminder integration exceeded 600 seconds")
                        for key, _ in selector.select(timeout=0.5):
                            chunk = os.read(key.fileobj.fileno(), 65536)
                            if not chunk:
                                selector.unregister(key.fileobj)
                                continue
                            sys.stdout.buffer.write(chunk)
                            sys.stdout.buffer.flush()
                            buffer += chunk
                            while b"\n" in buffer:
                                line, buffer = buffer.split(b"\n", 1)
                                marker = b"VITAL_REMINDER_ACTION:"
                                if marker not in line:
                                    continue
                                if driven:
                                    raise RuntimeError("Unexpected repeated action driver request")
                                action = json.loads(line.split(marker, 1)[1])
                                if action.get("action") != "snooze" or any(
                                    not isinstance(action.get(field), str) or
                                    not re.fullmatch(r"(?:[0-9a-f]{32}|[0-9a-f]{48})", action[field])
                                    for field in ("epoch", "requestToken", "actionToken")):
                                    raise RuntimeError("Invalid synthetic action envelope")
                                uri = "vital-reminder://action/{epoch}/{requestToken}/snooze/{actionToken}".format(**action)
                                for _ in range(2):
                                    adb("shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity",
                                        "-a", "dev.truegrit.vital.REMINDER", "-d", uri)
                                driven = True
                                evidence["synthetic_activity_deliveries"] = 2
                                encrypted = subprocess.run([
                                    "adb", "-s", args.device, "exec-out", "run-as", PACKAGE,
                                    "cat", "no_backup/reminders-v1/journal.enc"],
                                    capture_output=True, check=True, timeout=60).stdout
                                absent = all(action[field].encode() not in encrypted
                                             for field in ("epoch", "requestToken", "actionToken"))
                                if not 29 <= len(encrypted) <= 8 * 1024 * 1024 or not absent:
                                    raise RuntimeError("Protected reminder journal inspection failed")
                                evidence["reminder_journal"] = {
                                    "ciphertext_bytes": len(encrypted),
                                    "sha256": hashlib.sha256(encrypted).hexdigest(),
                                    "synthetic_tokens_absent": absent,
                                }
                    code = child.wait(timeout=max(1, deadline - time.monotonic()))
                    if not driven:
                        raise RuntimeError("Fixture did not request its synthetic Activity action")
                finally:
                    selector.close()
                    child.stdout.close()
                    if child.poll() is None:
                        os.killpg(child.pid, signal.SIGTERM)
                        try:
                            child.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            os.killpg(child.pid, signal.SIGKILL)
                            child.wait()
            evidence["tests"].append({"test": name, "exit_code": code})
            if code:
                break
    finally:
        # Restore on both success and test failure; preserve recovery material
        # if restoration/hash validation fails, rather than deleting it.
        try:
            evidence["snapshot_restored"] = "OK" in adb(
                "emu", "avd", "snapshot", "load", snapshot, timeout=120)
            adb("wait-for-device")
            evidence["encrypted_files_restored"] = hashes() == original
            evidence["reminder_journal_restored"] = reminder_hash() == original_reminder
            if (evidence["snapshot_restored"] and evidence["encrypted_files_restored"]
                    and evidence["reminder_journal_restored"]):
                evidence["snapshot_deleted"] = "OK" in adb(
                    "emu", "avd", "snapshot", "delete", snapshot)
            evidence["passed"] = bool(
                len(evidence["tests"]) == len(args.tests)
                and all(test["exit_code"] == 0 for test in evidence["tests"])
                and evidence.get("snapshot_restored")
                and evidence.get("encrypted_files_restored")
                and evidence.get("reminder_journal_restored")
                and evidence.get("snapshot_deleted"))
        finally:
            args.output.write_text(json.dumps(evidence, indent=2) + "\n")
    return 0 if evidence["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
