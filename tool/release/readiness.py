#!/usr/bin/env python3
"""Fail-closed release readiness checks for True Grit: Vital.

This tool proves only what it can inspect: the pinned toolchain, locked
resolution, dependency notices, Android release defaults, truthful release
metadata and the completeness of the tracked release obligations. Physical
devices, publisher/territory choices, signing secrets and store submission are
human-owned gates and are reported as open, never inferred.

Usage:
    python3 tool/release/readiness.py [--report PATH] [--run-verification]

Exit status: 0 when every automated check passes (open gates may remain),
1 when an automated check fails, 2 for usage errors.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"

SCREEN_IDS = [f"S{i:02d}" for i in range(1, 21)]
SHEET_IDS = [f"M{i:02d}" for i in range(1, 9)]
FAMILY_IDS = [f"SF{i:02d}" for i in range(1, 14)]
ACCEPTANCE_IDS = [f"C{i:02d}" for i in range(1, 13)]
GATE_IDS = [f"G{i:02d}" for i in range(1, 9)]
STORY_IDS = [f"US{i:02d}" for i in range(1, 79)]

ALLOWED_PERMISSIONS = {
    "android.permission.USE_BIOMETRIC",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.SCHEDULE_EXACT_ALARM",
    "android.permission.RECEIVE_BOOT_COMPLETED",
}

BACKUP_DOMAINS = (
    "root",
    "file",
    "database",
    "sharedpref",
    "external",
    "device_root",
    "device_file",
    "device_database",
    "device_sharedpref",
)


class Result:
    def __init__(self, check: str) -> None:
        self.check = check
        self.failures: list[str] = []
        self.opens: list[str] = []

    def require(self, condition: bool, message: str) -> None:
        if not condition:
            self.failures.append(message)

    def open(self, message: str) -> None:
        self.opens.append(message)

    @property
    def passed(self) -> bool:
        return not self.failures


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        raise AssertionError(f"unable to read {path.relative_to(ROOT)}: {error}") from error


def pubspec_direct_dependencies(text: str) -> dict[str, str]:
    lines = text.splitlines()
    try:
        start = lines.index("dependencies:")
    except ValueError as error:
        raise AssertionError("pubspec.yaml has no dependencies block") from error
    dependencies: dict[str, str] = {}
    current: str | None = None
    for line in lines[start + 1 :]:
        if line and not line.startswith((" ", "\t")):
            break
        match = re.match(r"^  ([a-zA-Z0-9_]+):(.*)$", line)
        if match:
            current = match.group(1)
            dependencies[current] = match.group(2).strip()
        elif current and "sdk:" in line:
            dependencies[current] = "sdk"
    return {
        name: value
        for name, value in dependencies.items()
        if "sdk" not in value and not value.startswith("path:")
    }


def notice_covers(licence_dir: Path, package: str) -> bool:
    for path in licence_dir.iterdir():
        if not path.is_file():
            continue
        if path.name == package or path.name.startswith((package + "-", package + ".")):
            return True
    return False


def lockfile_packages(lock_text: str) -> list[tuple[str, str]]:
    """Return every hosted package and version in the resolved lockfile."""
    pattern = (
        r"^  ([a-zA-Z0-9_]+):\n"
        r"    dependency: [^\n]+\n"
        r"    description:\n"
        r"(?:      [^\n]*\n)*?"
        r"    source: hosted\n"
        r"    version: \"?([^\"\n]+)\"?"
    )
    return [(name, version) for name, version in re.findall(pattern, lock_text, re.MULTILINE)]


def combined_notice_packages(licence_dir: Path) -> set[str]:
    """Package names recorded as sections in the combined adopted-package notice."""
    combined = licence_dir / "16-adopted-package-NOTICES.txt"
    if not combined.is_file():
        return set()
    return set(
        re.findall(r"^===== (\S+) ", read(combined), re.MULTILINE)
    )


def check_toolchain(root: Path) -> Result:
    result = Result("toolchain")
    pin = read(root / ".flutter-version").strip()
    pubspec = read(root / "pubspec.yaml")
    result.require(pin == "3.47.7", f".flutter-version is {pin}, expected 3.47.7")
    result.require(
        "sdk: '>=3.13.5 <4.0.0'" in pubspec,
        "pubspec Dart constraint is not the pinned >=3.13.5 <4.0.0",
    )
    result.require(
        "flutter: '>=3.47.7'" in pubspec,
        "pubspec Flutter constraint is not the pinned >=3.47.7",
    )
    wrapper = read(root / "tool/flutterw")
    result.require(
        "expected_flutter" in wrapper and "3.13.5" in wrapper,
        "tool/flutterw no longer verifies both pinned SDK versions",
    )
    return result


def check_dependencies(root: Path) -> Result:
    result = Result("dependencies")
    lock_path = root / "pubspec.lock"
    result.require(lock_path.is_file(), "pubspec.lock is missing")
    if not lock_path.is_file():
        return result
    lock = read(lock_path)
    result.require('source: "hosted"' in lock or "source: hosted" in lock, "no hosted resolution present")
    result.require("source: git" not in lock, "a git dependency is locked")
    result.require(
        "  dart: \">=3.13.5 <4.0.0\"" in lock,
        "lockfile SDK constraint does not match the pinned Dart SDK",
    )
    result.require(
        "  flutter: \">=3.47.7\"" in lock,
        "lockfile Flutter constraint does not match the pinned SDK",
    )
    pubspec = read(root / "pubspec.yaml")
    overrides = re.search(r"^dependency_overrides:\n((?:  .*\n)+)", pubspec, re.MULTILINE)
    if overrides:
        block = overrides.group(1)
        result.require(
            block.strip() == "pdfium_dart:\n    path: third_party/pdfium_dart",
            "dependency_overrides contains an unapproved override",
        )
        result.require(
            (root / "third_party/pdfium_dart/pubspec.yaml").is_file(),
            "the pdfium_dart override path is missing",
        )
    return result


def check_licences(root: Path) -> Result:
    result = Result("licences")
    licence_dir = root / "docs/implementation/licenses"
    result.require(licence_dir.is_dir(), "licence notice directory is missing")
    if not licence_dir.is_dir():
        return result
    result.require(
        (root / "LICENSE").is_file() and read(root / "LICENSE").startswith("MIT License"),
        "the project MIT licence is missing or changed",
    )
    combined = combined_notice_packages(licence_dir)
    for package in sorted(pubspec_direct_dependencies(read(root / "pubspec.yaml"))):
        result.require(
            notice_covers(licence_dir, package) or package in combined,
            f"no notice file covers direct dependency {package}",
        )
    lock_path = root / "pubspec.lock"
    packages = lockfile_packages(read(lock_path)) if lock_path.is_file() else []
    result.require(bool(packages), "no hosted packages could be read from pubspec.lock")
    for package, version in packages:
        result.require(
            notice_covers(licence_dir, package) or package in combined,
            f"no notice covers resolved package {package} {version}",
        )
    audit_path = root / 'tool/release/package_licences.json'
    result.require(audit_path.is_file(), 'version-bound package licence audit is missing')
    if audit_path.is_file():
        audit = json.loads(read(audit_path))
        entries = audit.get('packages', [])
        by_name = {entry['name']: entry for entry in entries}
        result.require(len(by_name) == len(entries), 'package licence audit contains duplicate names')
        for package, version in packages:
            entry = by_name.get(package)
            result.require(entry is not None and entry.get('version') == version,
                           f'licence audit does not cover exact version {package} {version}')
            if entry is None:
                continue
            notice = root / entry.get('notice', '')
            result.require(notice.is_file() and
                           hashlib.sha256(notice.read_bytes()).hexdigest() == entry.get('noticeSha256'),
                           f'audited notice changed or is missing for {package} {version}')
            block = re.search(r'^  ' + re.escape(package) + r':\n(.*?)(?=^  \w|^sdks:|\Z)',
                              read(lock_path), re.MULTILINE | re.DOTALL)
            digest = re.search(r'^      sha256: "?([^"\n]+)', block.group(1), re.MULTILINE) if block else None
            result.require((digest.group(1) if digest else None) == entry.get('archiveSha256'),
                           f'licence audit archive hash differs for {package} {version}')
    result.require(
        (root / "third_party/pdfium_dart/LICENSE").is_file(),
        "the vendored pdfium_dart licence is missing",
    )
    result.require(
        any(licence_dir.glob("pdfium-*-NOTICES.txt")),
        "the PDFium native notices are missing",
    )
    result.require(
        (licence_dir / "sqlite3mc-2.6.1-THIRD_PARTY_NOTICES.txt").is_file(),
        "the SQLite3MC third-party notices are missing",
    )
    return result


def backup_rule_file_excludes_all(path: Path, sections: tuple[str, ...]) -> list[str]:
    problems: list[str] = []
    try:
        tree = ET.parse(path)
    except (OSError, ET.ParseError) as error:
        return [f"{path.name} is not readable XML: {error}"]
    for section in sections:
        node = tree.getroot() if section == "" else tree.getroot().find(section)
        if node is None:
            problems.append(f"{path.name} has no {section or 'root'} section")
            continue
        excluded = {
            (element.get("domain"), element.get("path"))
            for element in node.findall("exclude")
        }
        for domain in BACKUP_DOMAINS:
            if (domain, ".") not in excluded and (domain, "") not in excluded:
                problems.append(f"{path.name} does not exclude {domain} data")
    return problems


def check_android(root: Path) -> Result:
    result = Result("android-release-config")
    manifest_path = root / "android/app/src/main/AndroidManifest.xml"
    gradle_path = root / "android/app/build.gradle.kts"
    result.require(manifest_path.is_file(), "main AndroidManifest.xml is missing")
    result.require(gradle_path.is_file(), "app build.gradle.kts is missing")
    if not (manifest_path.is_file() and gradle_path.is_file()):
        return result

    try:
        manifest = ET.parse(manifest_path).getroot()
    except ET.ParseError as error:
        result.require(False, f"AndroidManifest.xml is not valid XML: {error}")
        return result

    application = manifest.find("application")
    result.require(application is not None, "manifest has no application element")
    if application is None:
        return result

    result.require(
        application.get(ANDROID_NS + "allowBackup") == "false",
        "application allowBackup is not false",
    )
    result.require(
        application.get(ANDROID_NS + "debuggable") is None,
        "application declares android:debuggable",
    )
    result.require(
        (application.get(ANDROID_NS + "usesCleartextTraffic") or "").lower() != "true",
        "application permits cleartext traffic",
    )
    for attribute in ("fullBackupContent", "dataExtractionRules"):
        reference = application.get(ANDROID_NS + attribute)
        result.require(reference is not None, f"application has no {attribute} policy")
        if reference and reference.startswith("@xml/"):
            result.require(
                (root / "android/app/src/main/res/xml" / (reference.removeprefix("@xml/") + ".xml")).is_file(),
                f"{attribute} references a missing XML resource",
            )

    permissions = {
        element.get(ANDROID_NS + "name")
        for element in manifest.findall("uses-permission")
    }
    unexpected = permissions - ALLOWED_PERMISSIONS
    result.require(
        not unexpected,
        "unexpected Android permissions: " + ", ".join(sorted(str(item) for item in unexpected)),
    )

    android_exported = ANDROID_NS + "exported"
    for tag in ("activity", "activity-alias", "provider", "receiver", "service"):
        for element in application.findall(tag):
            name = element.get(ANDROID_NS + "name") or "?"
            if element.get(android_exported) == "true":
                launcher = any(
                    action.get(ANDROID_NS + "name") == "android.intent.action.MAIN"
                    for filter_node in element.findall("intent-filter")
                    for action in filter_node.findall("action")
                )
                result.require(
                    tag == "activity" and name == ".MainActivity" and launcher,
                    f"unexpected exported component {tag} {name}",
                )
            if name == ".MainActivity":
                result.require(
                    element.get(android_exported) == "true",
                    "MainActivity must remain exported for the launcher",
                )

    rules = root / "android/app/src/main/res/xml"
    for name, sections in (
        ("backup_rules.xml", ("",)),
        ("data_extraction_rules.xml", ("cloud-backup", "device-transfer")),
    ):
        if (rules / name).is_file():
            result.failures.extend(backup_rule_file_excludes_all(rules / name, sections))
        else:
            result.require(False, f"{name} is missing")

    gradle = read(gradle_path)
    result.require(
        'applicationId = "dev.truegrit.vital"' in gradle,
        "the application id is no longer the reviewed development identity",
    )
    result.require(
        'signingConfigs.getByName("debug")' not in gradle,
        "release signing falls back to the debug signing config",
    )
    result.require(
        "assembleRelease" in gradle and "bundleRelease" in gradle,
        "there is no fail-closed guard for release artifacts",
    )
    result.require(
        "Release signing is not configured" in gradle,
        "the release guard does not state why the build fails closed",
    )
    release_block = re.search(r"release\s*\{(.*?)\n        \}", gradle, re.DOTALL)
    if release_block:
        result.require(
            re.search(r'signingConfig[^\n]*debug|getByName\("debug"\)', release_block.group(1))
            is None,
            "the release build type references debug signing",
        )
    else:
        result.require(False, "the release build type block could not be found")
    return result


def check_release_metadata(root: Path) -> Result:
    result = Result("release-metadata")
    readme = read(root / "README.md")
    status = read(root / "docs/public/STATUS.md")
    pubspec = read(root / "pubspec.yaml")
    version = re.search(r"^version: (.+)$", pubspec, re.MULTILINE)
    result.require(version is not None, "pubspec version is missing")
    if version:
        result.require(
            re.fullmatch(r"\d+\.\d+\.\d+\+\d+", version.group(1).strip()) is not None,
            f"pubspec version {version.group(1)!r} is not a build-numbered semantic version",
        )
    result.require("3.47.7" in readme, "README does not state the pinned Flutter version")
    result.require(".flutter-version" in readme, "README does not point to the SDK pin")
    result.require("MIT licence" in readme, "README does not state the source licence")
    result.require(
        "Release builds fail closed" in readme,
        "README does not state the fail-closed release signing policy",
    )
    result.require(
        "refuses release builds until owner-supplied signing" in status,
        "public status does not state the release signing limitation",
    )

    capabilities = json.loads(read(root / "tool/release/capabilities.json"))
    for capability in capabilities["capabilities"]:
        detection = [root / path for path in capability["detection"]]
        present = any(path.exists() for path in detection)
        if capability["status"] == "available":
            result.require(present, f"{capability['id']} is marked available but no module exists")
            continue
        result.require(
            not present,
            f"{capability['id']} now exists; update tool/release/capabilities.json and release metadata",
        )
        for marker in capability["readmeMarkers"]:
            result.require(
                marker in readme,
                f"README no longer describes {capability['id']} as unavailable ({marker!r})",
            )
        for marker in capability["statusMarkers"]:
            result.require(
                marker in status,
                f"public status no longer describes {capability['id']} as unavailable ({marker!r})",
            )
    return result


def validate_obligations(root: Path, data: dict) -> Result:
    result = Result("obligations")

    def require_ids(section: str, expected: list[str]) -> None:
        items = data.get(section, [])
        ids = [item.get("id") for item in items]
        result.require(len(ids) == len(set(ids)), f"{section} contains duplicate ids")
        result.require(
            ids == expected,
            f"{section} does not cover exactly {expected[0]}..{expected[-1]}",
        )

    require_ids("stories", STORY_IDS)
    require_ids("screens", SCREEN_IDS)
    require_ids("sheets", SHEET_IDS)
    require_ids("scheduleFamilies", FAMILY_IDS)
    require_ids("acceptanceObligations", ACCEPTANCE_IDS)
    require_ids("gates", GATE_IDS)

    def exists(path_text: str) -> bool:
        if not path_text:
            return False
        path = root / path_text.split("#", 1)[0]
        return path.exists()

    for story in data.get("stories", []):
        scope = f"story {story.get('id')}"
        result.require(
            story.get("implementation") in {"done", "partial", "planned"},
            f"{scope} has an unknown implementation state",
        )
        result.require(
            story.get("verification") in {"host-tested", "open", "external"},
            f"{scope} has an unknown verification state",
        )
        result.require(bool(story.get("owner")), f"{scope} has no owner")
        tests = story.get("tests", [])
        if story.get("verification") == "host-tested":
            result.require(bool(tests), f"{scope} claims host testing with no test path")
            result.require(all(exists(path) for path in tests), f"{scope} names a missing test path")
        if story.get("implementation") == "planned":
            result.require(not tests, f"{scope} is planned but lists test evidence")
            result.require(bool(story.get("gate")), f"{scope} is planned without an owning gate")
        if story.get("gate"):
            result.require(story["gate"] in GATE_IDS, f"{scope} references an unknown gate")

    routes_source = read(root / "lib/app/vital_app.dart")
    for screen in data.get("screens", []):
        scope = f"screen {screen.get('id')}"
        result.require(
            screen.get("state") in {"implemented", "partial", "planned"}, f"{scope} has an unknown state"
        )
        result.require(bool(screen.get("owner")), f"{scope} has no owner")
        route = screen.get("route", "")
        if screen.get("state") == "planned":
            result.require(route == "", f"{scope} is planned but declares a route")
        elif screen.get("state") == "implemented":
            result.require(bool(route), f"{scope} is implemented but has no route")
            if route:
                result.require(
                    f"path: '{route}'" in routes_source or f"('{route}'" in routes_source,
                    f"{scope} route {route} is not registered",
                )

    for sheet in data.get("sheets", []):
        scope = f"sheet {sheet.get('id')}"
        result.require(bool(sheet.get("owner")), f"{scope} has no owner")
        result.require(
            all(exists(path) for path in sheet.get("evidence", [])),
            f"{scope} names a missing evidence path",
        )

    for family in data.get("scheduleFamilies", []):
        scope = f"schedule family {family.get('id')}"
        result.require(bool(family.get("owner")), f"{scope} has no owner")
        result.require(
            bool(family.get("evidence")) and all(exists(path) for path in family.get("evidence", [])),
            f"{scope} has no existing evidence path",
        )

    for obligation in data.get("acceptanceObligations", []):
        scope = f"obligation {obligation.get('id')}"
        result.require(bool(obligation.get("owner")), f"{scope} has no owner")
        result.require(
            obligation.get("status") in {"open", "partially-verified", "verified"},
            f"{scope} has an unknown status",
        )
        result.require(bool(obligation.get("requiredEvidence")), f"{scope} has no required evidence")
        result.require(exists(obligation.get("reference", "")), f"{scope} reference does not exist")
        result.require(
            all(exists(path) for path in obligation.get("evidenceTests", [])),
            f"{scope} names a missing test path",
        )

    for gate in data.get("gates", []):
        scope = f"gate {gate.get('id')}"
        status = gate.get("status")
        result.require(status in {"open", "partially-verified", "passed"}, f"{scope} has an unknown status")
        result.require(bool(gate.get("owner")), f"{scope} has no owner")
        result.require(bool(gate.get("requiredEvidence")), f"{scope} has no required evidence")
        evidence = gate.get("evidence", [])
        result.require(
            all(exists(path) for path in evidence), f"{scope} names missing evidence"
        )
        if status in {"partially-verified", "passed"}:
            result.require(bool(evidence), f"{scope} claims progress with no evidence")
        if status == "passed":
            result.require(bool(gate.get("reviewer")), f"{scope} is passed without a reviewer")
    return result


def check_boot_fixture(root: Path) -> Result:
    result = Result("boot-fixture")
    test_path = root / "test/release/boot_smoke_test.dart"
    result.require(test_path.is_file(), "the host boot smoke test is missing")
    if test_path.is_file():
        source = read(test_path)
        result.require("VitalApp" in source, "the boot smoke test does not boot VitalApp")
        result.require("ProviderScope" in source, "the boot smoke test has no provider container")
        result.require(
            "storeLoaderProvider" in source,
            "the boot smoke test does not inject isolated storage",
        )
        result.require("Directory.systemTemp" in source, "the boot smoke test is not synthetic")
    matrix = root / "tool/release/boot_matrix.py"
    result.require(matrix.is_file(), "the boot matrix runner is missing")
    result.require(
        (root / "tool/release/BOOT_MATRIX.md").is_file(),
        "the boot matrix instructions are missing",
    )
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--report",
        default=str(ROOT / "build/release-readiness.json"),
        help="Write the machine-readable report here.",
    )
    parser.add_argument(
        "--run-verification",
        action="store_true",
        help="Run ./tool/verify checks and record its actual result (slow).",
    )
    args = parser.parse_args(argv)

    results = [
        check_toolchain(ROOT),
        check_dependencies(ROOT),
        check_licences(ROOT),
        check_android(ROOT),
        check_release_metadata(ROOT),
        check_boot_fixture(ROOT),
    ]

    obligations = json.loads(read(ROOT / "tool/release/obligations.json"))
    results.append(validate_obligations(ROOT, obligations))

    verification: dict[str, object] = {"ran": False, "passed": None, "detail": "not run"}
    if args.run_verification:
        process = subprocess.run(
            [str(ROOT / "tool/verify"), "checks"],
            cwd=ROOT,
            text=True,
        )
        verification = {
            "ran": True,
            "passed": process.returncode == 0,
            "detail": f"exit {process.returncode}",
        }
        result = Result("verification")
        result.require(process.returncode == 0, "tool/verify checks failed")
        results.append(result)

    failures = [f"{result.check}: {fail}" for result in results for fail in result.failures]
    opens = [f"{result.check}: {open_item}" for result in results for open_item in result.opens]

    gate_states = {gate["id"]: gate["status"] for gate in obligations["gates"]}
    open_gates = [gate for gate, state in gate_states.items() if state != "passed"]
    open_stories = [
        story["id"]
        for story in obligations["stories"]
        if story["verification"] != "host-tested" or story["implementation"] != "done"
    ]
    open_obligations = [
        obligation["id"]
        for obligation in obligations["acceptanceObligations"]
        if obligation["status"] != "verified"
    ]

    for result in results:
        if result.passed:
            print(f"PASS {result.check}")
    for line in failures:
        print(f"FAIL {line}")
    for line in opens:
        print(f"OPEN {line}")
    partial_gates = [gate for gate, state in gate_states.items() if state == "partially-verified"]
    print(
        f"GATES not-passed={len(open_gates)} open={len(open_gates) - len(partial_gates)} "
        f"partial={len(partial_gates)} ({', '.join(open_gates)}) "
        f"stories-open={len(open_stories)} acceptance-open={len(open_obligations)}"
    )
    if verification["ran"]:
        print(f"VERIFICATION {verification['detail']}")
    else:
        print("VERIFICATION not run (pass --run-verification for the full suite)")

    automated_passed = not failures
    print(
        "RESULT automated-preflight="
        + ("pass" if automated_passed else "fail")
        + "; pilot-ready=false (open gates and physical evidence remain); "
        + "release-ready=false (human release authorisation and signing are owner-owned)"
    )

    report = {
        "generatedAt": "2026-10-20",
        "baseCommit": "da0ec27692a42130d606eb1003a529c0aa1df6b5",
        "automatedPreflight": "pass" if automated_passed else "fail",
        "checks": [
            {"check": result.check, "passed": result.passed, "failures": result.failures}
            for result in results
        ],
        "openWarnings": opens,
        "verification": verification,
        "gates": gate_states,
        "openGates": open_gates,
        "openStories": open_stories,
        "openAcceptanceObligations": open_obligations,
        "pilotReady": False,
        "releaseReady": False,
        "releaseLimitations": [
            "Physical Android device, TalkBack, performance and lifecycle evidence is absent.",
            "Publisher, territory, privacy, store claims and release authorisation are owner-owned.",
            "Owner-supplied release signing is not configured; release builds fail closed.",
            "Report, export, backup/restore, privacy and reminder hardening work is not integrated in this tree.",
        ],
    }
    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"REPORT {report_path}")
    return 0 if automated_passed else 1


if __name__ == "__main__":
    sys.exit(main())
