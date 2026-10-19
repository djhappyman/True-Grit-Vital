#!/usr/bin/env python3
"""Verify real OS auth on a dedicated AVD; never run against a physical phone.

Uses an encrypted disposable Flutter fixture and a synthetic AVD PIN. The normal
dataset is only hashed as encrypted bytes. Restores the credential-free/disabled-screen
state only after the Dart fixture confirms its app lock is disabled.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "dev.truegrit.vital"
PIN = "246810"  # Public synthetic test fixture, never a human credential.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="emulator-5556")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--saved-snapshot", help="Existing task-owned vital04-auth-* baseline snapshot")
    args = parser.parse_args()
    if not args.device.startswith("emulator-"):
        parser.error("Only a disposable Android emulator is permitted")

    def adb(*words, check=True, timeout=20):
        return subprocess.run(["adb", "-s", args.device, *words], check=check,
                              capture_output=True, text=True, timeout=timeout).stdout

    if adb("shell", "getprop", "ro.kernel.qemu").strip() != "1":
        raise RuntimeError("Target is not a verified emulator")
    original_disabled = adb("shell", "locksettings", "get-disabled").strip()
    verified = adb("shell", "locksettings", "verify")
    if "verified successfully" not in verified:
        raise RuntimeError("AVD must start without a credential")
    original_files = adb("shell", "run-as", PACKAGE, "sha256sum",
                         "no_backup/vital/records.sqlite", "no_backup/vital/key-envelope.json")
    snapshot = args.saved_snapshot or f"vital04-auth-{time.time_ns()}"
    if not re.fullmatch(r"vital04-auth-[a-zA-Z0-9-]+", snapshot):
        raise RuntimeError("Snapshot must have this harness's exact task prefix")
    if not args.saved_snapshot:
        if "OK" not in adb("emu", "avd", "snapshot", "save", snapshot, timeout=120):
            raise RuntimeError("Could not snapshot the original AVD data and Keystore")
    evidence = {"device": args.device, "api": adb("shell", "getprop", "ro.build.version.sdk").strip(),
                "synthetic_pin": True, "original_lock_disabled": original_disabled,
                "baseline_snapshot": snapshot, "checks": []}
    # Clear only acknowledgements owned by this exact harness.
    steps = ["initial-secure", "setup-required-off", "configure-pin", "cancel-keeps-off",
             "enabled-secure", "background-return", "cancel-stays-locked",
             "unlocked-secure", "disabled-unsecured"]
    for name in steps:
        adb("shell", "run-as", PACKAGE, "rm", "-f", f"cache/vital-auth-ack-{name}", check=False)
    adb("shell", "run-as", PACKAGE, "rm", "-f", "cache/vital-auth-driver-error", check=False)
    temp_path = None

    def test_file(name):
        if temp_path is None:
            raise RuntimeError("Native test did not provide its temporary directory")
        return f"{temp_path}/vital-auth-{name}"

    def ack(name):
        adb("shell", "run-as", PACKAGE, "touch", test_file(f"ack-{name}"))

    def secure(expected):
        dump = adb("shell", "dumpsys", "window", "windows")
        app = [part for part in re.split(r"(?=  Window #\d+ Window\{)", dump)
               if re.match(r"  Window #\d+ Window\{[^\n]*dev\.truegrit\.vital/", part)]
        if not app:
            raise RuntimeError("Vital Activity window is missing")
        actual = any(re.search(r"\bSECURE\b", part.split("Requested w=", 1)[0]) for part in app)
        if actual != expected:
            raise RuntimeError(f"Vital SECURE flag expected {expected}, got {actual}")
        return actual

    def credential_prompt():
        for _ in range(40):
            adb("shell", "uiautomator", "dump", "/data/local/tmp/vital04-auth.xml", check=False)
            xml = adb("shell", "cat", "/data/local/tmp/vital04-auth.xml", check=False)
            try:
                nodes = list(ET.fromstring(xml).iter("node"))
            except ET.ParseError:
                time.sleep(0.25)
                continue
            if any("lockPassword" in n.get("resource-id", "") or
                   "pin" in n.get("text", "").lower() or
                   n.get("class") == "android.widget.EditText" for n in nodes):
                return nodes
            time.sleep(0.25)
        raise RuntimeError("OS credential prompt did not appear")

    def act(name):
        if name in ("initial-secure", "enabled-secure", "cancel-stays-locked", "unlocked-secure"):
            evidence["checks"].append({"step": name, "secure": secure(True)})
            ack(name)
        elif name in ("setup-required-off", "cancel-keeps-off", "disabled-unsecured"):
            evidence["checks"].append({"step": name, "secure": secure(False)})
            ack(name)
        elif name == "configure-pin":
            response = adb("shell", "locksettings", "set-pin", PIN)
            if "set to" not in response:
                raise RuntimeError("Synthetic AVD PIN could not be configured")
            evidence["checks"].append({"step": name, "configured": True})
            ack(name)
        elif name.startswith("cancel-"):
            credential_prompt()
            adb("shell", "input", "keyevent", "KEYCODE_BACK")
            evidence["checks"].append({"step": name, "os_cancel": True})
        elif name in ("enable-pin", "unlock-pin", "disable-pin"):
            nodes = credential_prompt()
            fields = [n for n in nodes if n.get("class") == "android.widget.EditText"]
            if fields:
                bounds = re.findall(r"\d+", fields[0].get("bounds", ""))
                if len(bounds) == 4:
                    x1, y1, x2, y2 = map(int, bounds)
                    adb("shell", "input", "tap", str((x1+x2)//2), str((y1+y2)//2))
            adb("shell", "input", "text", PIN)
            adb("shell", "input", "keyevent", "KEYCODE_ENTER")
            evidence["checks"].append({"step": name, "os_pin_submitted": True})
        elif name == "background-return":
            adb("shell", "input", "keyevent", "KEYCODE_HOME")
            time.sleep(1)
            adb("shell", "am", "start", "-n", f"{PACKAGE}/.MainActivity")
            time.sleep(1)
            evidence["checks"].append({"step": name, "secure": secure(True)})
            ack(name)
        else:
            raise RuntimeError(f"Unexpected test step {name}")

    process = subprocess.Popen([str(ROOT / "tool/flutterw"), "test", "--no-pub", "-d", args.device,
                                "integration_test/app_auth_native_test.dart"], cwd=ROOT,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    lock_disabled = False
    error = None
    deadline = threading.Timer(420, process.kill)
    deadline.start()
    try:
        for line in process.stdout:
            print(line, end="", flush=True)
            location = re.search(r"VITAL_AUTH_TEMP:(/[^\r\n]+)", line)
            if location:
                candidate = location.group(1).strip()
                if not (candidate.startswith(f"/data/user/0/{PACKAGE}/") or
                        candidate.startswith(f"/data/data/{PACKAGE}/")):
                    raise RuntimeError("Unexpected native test temporary directory")
                temp_path = candidate
            if "VITAL_AUTH_LOCK_DISABLED" in line:
                lock_disabled = True
            outcome = re.search(r"VITAL_AUTH_RESULT:([a-zA-Z]+):([a-zA-Z]+)", line)
            if outcome:
                evidence["checks"].append({"native_result": outcome.group(1), "flutter_lifecycle": outcome.group(2)})
            marker = re.search(r"VITAL_AUTH_STEP:([a-z-]+)", line)
            if marker:
                try:
                    act(marker.group(1))
                except Exception as failure:
                    error = str(failure)
                    adb("shell", "input", "keyevent", "KEYCODE_BACK", check=False)
                    adb("shell", "run-as", PACKAGE, "touch", test_file("driver-error"), check=False)
                    if marker.group(1) in steps:
                        ack(marker.group(1))
        result = process.wait(timeout=20)
        evidence["exit_code"] = result
        evidence["passed"] = result == 0 and error is None
    finally:
        deadline.cancel()
        if process.poll() is None:
            process.kill()
            process.wait(timeout=20)
        if lock_disabled:
            response = adb("shell", "locksettings", "clear", "--old", PIN, check=False)
            # If setup failed before adding a PIN, there is nothing to clear.
            evidence["credential_cleared"] = "verified successfully" in adb("shell", "locksettings", "verify", check=False)
            adb("shell", "locksettings", "set-disabled", original_disabled)
            evidence["lock_disabled_restored"] = adb("shell", "locksettings", "get-disabled").strip() == original_disabled
        else:
            evidence["credential_cleanup_withheld"] = "Dart did not confirm app lock disabled; preserve AVD for recovery"
        for name in steps:
            adb("shell", "run-as", PACKAGE, "rm", "-f", f"cache/vital-auth-ack-{name}", check=False)
            if temp_path is not None:
                adb("shell", "run-as", PACKAGE, "rm", "-f", test_file(f"ack-{name}"), check=False)
        adb("shell", "run-as", PACKAGE, "rm", "-f", "cache/vital-auth-driver-error", check=False)
        if temp_path is not None:
            adb("shell", "run-as", PACKAGE, "rm", "-f", test_file("driver-error"), check=False)
        adb("shell", "rm", "-f", "/data/local/tmp/vital04-auth.xml", check=False)
        if error:
            evidence["error"] = error
        if lock_disabled:
            restored = adb("emu", "avd", "snapshot", "load", snapshot, timeout=120)
            evidence["baseline_snapshot_restored"] = "OK" in restored
            adb("wait-for-device", timeout=60)
            evidence["original_credential_empty"] = "verified successfully" in adb("shell", "locksettings", "verify", check=False)
            evidence["original_disabled_screen_restored"] = adb("shell", "locksettings", "get-disabled").strip() == original_disabled
            evidence["original_encrypted_database_and_envelope_restored"] = original_files == adb(
                "shell", "run-as", PACKAGE, "sha256sum", "no_backup/vital/records.sqlite",
                "no_backup/vital/key-envelope.json")
            if (evidence["baseline_snapshot_restored"] and evidence["original_credential_empty"]
                    and evidence["original_disabled_screen_restored"]
                    and evidence["original_encrypted_database_and_envelope_restored"]):
                evidence["task_snapshot_deleted"] = "OK" in adb("emu", "avd", "snapshot", "delete", snapshot, timeout=60)
        evidence["passed"] = bool(evidence.get("passed") and lock_disabled
                                  and evidence.get("original_credential_empty")
                                  and evidence.get("original_disabled_screen_restored")
                                  and evidence.get("original_encrypted_database_and_envelope_restored")
                                  and evidence.get("task_snapshot_deleted"))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(evidence, indent=2) + "\n")
    return 0 if evidence.get("passed") else 1


if __name__ == "__main__":
    sys.exit(main())
