#!/usr/bin/env python3
"""Self-test generation, validation, determinism and overwrite safety.

Run from any directory:

    python3 tool/fixtures/attachments/selftest.py

The test uses a temporary directory only. It starts no Flutter, device, UI or
network process and installs nothing.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
GENERATE = HERE / "generate.py"
VALIDATE = HERE / "validate.py"
INPUT_LIMIT = 131072
SIZES = "1024,131071,131072,131073,200000"
ENV = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}


def run(command: list[str], expect: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [sys.executable, *command],
        text=True,
        capture_output=True,
        cwd=REPO,
        env=ENV,
    )
    if result.returncode != expect:
        raise AssertionError(
            f"command {' '.join(command)} returned {result.returncode}, "
            f"expected {expect}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def manifest(directory: Path) -> dict[str, object]:
    return json.loads((directory / "manifest.json").read_text(encoding="utf-8"))


def file_hashes(directory: Path) -> dict[str, str]:
    result = {}
    for path in sorted(directory.iterdir()):
        if path.name == "manifest.json":
            continue
        result[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def generate(output: Path, *, sizes: str = SIZES, replace: bool = False) -> dict[str, object]:
    command = [
        str(GENERATE),
        "--output",
        str(output),
        "--input-limit",
        str(INPUT_LIMIT),
        "--sizes",
        sizes,
        "--json",
    ]
    if replace:
        command.append("--replace")
    return json.loads(run(command).stdout)


def validate(output: Path) -> dict[str, object]:
    return json.loads(run([str(VALIDATE), "--input", str(output), "--json"]).stdout)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="vital-attachment-fixture-selftest-") as raw:
        root = Path(raw)
        out1, out2 = root / "out1", root / "out2"
        summary1 = generate(out1)
        summary2 = generate(out2)
        assert summary1["fixtureCount"] == summary2["fixtureCount"], "fixture counts differ"
        assert summary1["totalFixtureBytes"] == summary2["totalFixtureBytes"], "byte totals differ"
        assert (out1 / "manifest.json").read_bytes() == (
            out2 / "manifest.json"
        ).read_bytes(), "manifests are not byte-identical"
        assert file_hashes(out1) == file_hashes(out2), "fixture hashes are not deterministic"
        print("PASS deterministic generation: identical manifests and hashes in two directories")

        assert summary1["maxWriteBufferBytes"] <= 64 * 1024, "generator used a large write buffer"
        assert summary1["peakTracedBytes"] < 8 * 1024 * 1024, "generator allocation exceeded 8 MiB"
        print(
            "PASS bounded generation: largest write "
            f"{summary1['maxWriteBufferBytes']} bytes, peak traced "
            f"{summary1['peakTracedBytes']} bytes"
        )

        report1 = validate(out1)
        assert report1["pass"] is True, "validator rejected its generated set"
        assert report1["maxReadBytes"] <= 64 * 1024, "validator made a large read"
        assert report1["peakTracedBytes"] <= 16 * 1024 * 1024, "validator allocation exceeded 16 MiB"
        print(
            "PASS validation: "
            f"{report1['fileCount']} fixtures, largest read {report1['maxReadBytes']} bytes, "
            f"peak traced {report1['peakTracedBytes']} bytes"
        )

        manifest_data = manifest(out1)
        files = {entry["name"]: entry for entry in manifest_data["files"]}  # type: ignore[index]
        bomb = files["image-decompression-bomb.png"]
        assert bomb["bytes"] < 64 * 1024, "PNG bomb is not small"
        assert bomb["declared_pixels"] > 16_000_000, "PNG bomb does not exceed the pixel limit"
        pdf_bomb = files["pdf-page-count-bomb.pdf"]
        assert pdf_bomb["bytes"] < 64 * 1024, "PDF bomb is not small"
        assert pdf_bomb["page_count"] > 100, "PDF bomb does not exceed the page limit"
        print("PASS metadata bombs stay tiny and are checked without pixel allocation")

        # A modified generated file must block replacement.
        (out1 / "empty.bin").write_bytes(b"changed")
        modified = run(
            [
                str(GENERATE),
                "--output",
                str(out1),
                "--input-limit",
                str(INPUT_LIMIT),
                "--sizes",
                SIZES,
                "--replace",
            ],
            expect=2,
        )
        assert "was modified" in modified.stderr, "modified file was not reported"
        shutil.copyfile(out2 / "empty.bin", out1 / "empty.bin")
        print("PASS replacement refusal: a modified generated file was preserved")

        # Unknown files must block replacement and remain untouched.
        (out1 / "unexpected.txt").write_text("keep me\n", encoding="utf-8")
        unknown = run(
            [
                str(GENERATE),
                "--output",
                str(out1),
                "--input-limit",
                str(INPUT_LIMIT),
                "--sizes",
                SIZES,
                "--replace",
            ],
            expect=2,
        )
        assert "did not generate" in unknown.stderr, "unknown file was not reported"
        assert (out1 / "unexpected.txt").read_text(encoding="utf-8") == "keep me\n"
        (out1 / "unexpected.txt").unlink()
        print("PASS replacement refusal: an unknown file was reported and preserved")

        generated = generate(out1, replace=True)
        assert generated["replaced"] is True, "replacement was not marked as a replacement"
        validate(out1)
        print("PASS replacement: a complete generated set was replaced and validated")

        # Changing the requested sizes must remove only stale generated files.
        generate(out1, sizes="1024", replace=True)
        assert not (out1 / "stream-at-byte-limit.bin").exists(), "stale stream was retained"
        assert (out1 / "stream-size-1024-bytes.bin").exists(), "new stream is missing"
        validate(out1)
        print("PASS replacement: stale generated sizes were removed; the new set validates")

        # A changed manifest hash must fail validation.
        tampered = root / "tampered"
        shutil.copytree(out1, tampered)
        bad = manifest(tampered)
        bad["files"][0]["sha256"] = "0" * 64  # type: ignore[index]
        (tampered / "manifest.json").write_text(
            json.dumps(bad, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        bad_result = run([str(VALIDATE), "--input", str(tampered), "--json"], expect=1)
        assert "hash does not match" in bad_result.stdout, "tampered hash was not detected"
        print("PASS validation refusal: a changed file hash was detected")

        # An unexpected file must fail validation.
        extra = root / "extra"
        shutil.copytree(out1, extra)
        (extra / "intruder.bin").write_bytes(b"x")
        extra_result = run([str(VALIDATE), "--input", str(extra), "--json"], expect=1)
        assert "Unexpected files" in extra_result.stdout, "extra file was not detected"
        print("PASS validation refusal: an unexpected file was detected")

        # Scope guards must refuse the repository root and a missing parent.
        scope = run(
            [
                str(GENERATE),
                "--output",
                str(REPO),
                "--input-limit",
                str(INPUT_LIMIT),
                "--sizes",
                "1024",
            ],
            expect=2,
        )
        assert "source directory or one of its parents" in scope.stderr
        missing = run(
            [
                str(GENERATE),
                "--output",
                str(root / "missing-parent" / "out"),
                "--input-limit",
                str(INPUT_LIMIT),
                "--sizes",
                "1024",
            ],
            expect=2,
        )
        assert "parent does not exist" in missing.stderr
        print("PASS scope refusal: repository root and missing parent were declined")

        link = root / "linked-output"
        link.symlink_to(out1, target_is_directory=True)
        linked = run(
            [
                str(GENERATE),
                "--output",
                str(link),
                "--input-limit",
                str(INPUT_LIMIT),
                "--sizes",
                "1024",
            ],
            expect=2,
        )
        assert "symbolic link" in linked.stderr, "symbolic-link output was not declined"
        print("PASS scope refusal: a symbolic-link output was declined")

        too_large = run(
            [
                str(GENERATE),
                "--output",
                str(root / "too-large"),
                "--input-limit",
                str(INPUT_LIMIT),
                "--sizes",
                str(300 * 1024 * 1024),
                "--json",
            ],
            expect=2,
        )
        assert "max-total-bytes" in too_large.stderr, "total-size guard did not run"
        assert not (root / "too-large").exists(), "guard created an output directory"
        print("PASS size guard: an oversized request was refused before writing")

    print("PASS all attachment fixture self-tests")
    print("Scope: synthetic structure, hashes, determinism and memory guards only.")
    print("No renderer, decoder, Flutter UI, device or network check was performed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
