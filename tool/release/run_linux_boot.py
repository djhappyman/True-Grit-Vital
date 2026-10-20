#!/usr/bin/env python3
"""Run the native boot check with a unique real keyring namespace."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-dir', type=Path, default=ROOT / 'build/linux-native-boot')
    args = parser.parse_args()
    directory = Path(tempfile.mkdtemp(prefix="vital-linux-boot-", dir="/tmp"))
    namespace = "dev.truegrit.vital.smoke." + uuid.uuid4().hex
    evidence = args.evidence_dir
    evidence.mkdir(parents=True, exist_ok=True)
    result = {
        "platform": "linux", "native": True, "realSecretService": True,
        "namespace": namespace, "temporaryDirectory": str(directory),
        "physicalAndroid": False,
    }
    command = [str(ROOT / "tool/flutterw"), "test", "--no-pub",
               "integration_test/linux_boot_test.dart", "-d", "linux",
               "--dart-define=VITAL_BOOT_DIRECTORY=" + str(directory),
               "--dart-define=VITAL_BOOT_NAMESPACE=" + namespace]
    with (evidence / "native-boot.log").open("w") as log:
        run = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    result["exitCode"] = run.returncode
    if run.returncode == 0:
        # Only the unique task-owned key is cleared. Never enumerate secrets.
        cleanup = subprocess.run(["/usr/bin/secret-tool", "clear", "application",
                                  namespace, "dataset", "main"], capture_output=True)
        result["secretCleanupExitCode"] = cleanup.returncode
        if cleanup.returncode == 0:
            shutil.rmtree(directory)
            result["temporaryDirectoryRemoved"] = True
    (evidence / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return run.returncode or result.get("secretCleanupExitCode", 0)


if __name__ == "__main__":
    raise SystemExit(main())
