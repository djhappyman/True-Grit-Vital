#!/usr/bin/env python3
"""Fail-closed regression tests for the release readiness preflight."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location(
    "vital_readiness", ROOT / "tool/release/readiness.py"
)
assert SPEC and SPEC.loader
readiness = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(readiness)


def minimal_android(root: Path, manifest: str, gradle: str) -> None:
    manifest_path = root / "android/app/src/main/AndroidManifest.xml"
    manifest_path.parent.mkdir(parents=True)
    manifest_path.write_text(manifest)
    (root / "android/app/build.gradle.kts").write_text(gradle)
    rules = root / "android/app/src/main/res/xml"
    rules.mkdir(parents=True)
    exclusions = "".join(
        f'<exclude domain="{domain}" path="." />' for domain in readiness.BACKUP_DOMAINS
    )
    (rules / "backup_rules.xml").write_text(
        f'<?xml version="1.0" encoding="utf-8"?><full-backup-content>{exclusions}'
        "</full-backup-content>"
    )
    (rules / "data_extraction_rules.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?><data-extraction-rules>'
        f"<cloud-backup>{exclusions}</cloud-backup>"
        f"<device-transfer>{exclusions}</device-transfer>"
        "</data-extraction-rules>"
    )


MANIFEST = """<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
  <application android:allowBackup="false"
      android:fullBackupContent="@xml/backup_rules"
      android:dataExtractionRules="@xml/data_extraction_rules">
    <activity android:name=".MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
      </intent-filter>
    </activity>
  </application>
</manifest>
"""

SAFE_GRADLE = """android {
    defaultConfig {
        applicationId = "dev.truegrit.vital"
    }
    buildTypes {
        release {
            // No signing material in source.
        }
    }
}

gradle.taskGraph.whenReady { graph ->
    val releaseRequested = graph.allTasks.any { task ->
        task.name.startsWith("assembleRelease") || task.name.startsWith("bundleRelease")
    }
    if (releaseRequested) {
        throw org.gradle.api.GradleException("Release signing is not configured.")
    }
}
"""


class AndroidConfigTest(unittest.TestCase):
    def test_repository_android_defaults_are_safe(self) -> None:
        result = readiness.check_android(ROOT)
        self.assertEqual(result.failures, [])

    def test_debug_signing_fallback_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            minimal_android(
                root,
                MANIFEST,
                SAFE_GRADLE.replace(
                    "// No signing material in source.",
                    'signingConfig = signingConfigs.getByName("debug")',
                ),
            )
            result = readiness.check_android(root)
            self.assertTrue(
                any("debug signing" in failure for failure in result.failures),
                result.failures,
            )

    def test_missing_release_guard_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            minimal_android(root, MANIFEST, 'applicationId = "dev.truegrit.vital"')
            result = readiness.check_android(root)
            self.assertTrue(
                any("fail-closed guard" in failure for failure in result.failures),
                result.failures,
            )

    def test_backup_policy_must_exclude_database(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            minimal_android(root, MANIFEST, SAFE_GRADLE)
            rules = root / "android/app/src/main/res/xml/backup_rules.xml"
            rules.write_text(
                '<?xml version="1.0" encoding="utf-8"?><full-backup-content>'
                '<exclude domain="root" path="." /></full-backup-content>'
            )
            result = readiness.check_android(root)
            self.assertTrue(
                any("does not exclude database data" in failure for failure in result.failures),
                result.failures,
            )

    def test_unexpected_network_permission_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            minimal_android(
                root,
                MANIFEST.replace(
                    '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
                    '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />'
                    '<uses-permission android:name="android.permission.INTERNET" />',
                ),
                SAFE_GRADLE,
            )
            result = readiness.check_android(root)
            self.assertTrue(
                any("unexpected Android permissions" in failure for failure in result.failures),
                result.failures,
            )


class LicenceTest(unittest.TestCase):
    def test_repository_notices_cover_every_resolved_package(self) -> None:
        result = readiness.check_licences(ROOT)
        self.assertEqual(result.failures, [])

    def test_missing_notice_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "docs/implementation/licenses").mkdir(parents=True)
            (root / "LICENSE").write_text("MIT License\n")
            (root / "pubspec.yaml").write_text(
                "dependencies:\n  flutter:\n    sdk: flutter\n  sample_package: 1.0.0\n"
            )
            (root / "pubspec.lock").write_text(
                "packages:\n"
                "  sample_package:\n"
                "    dependency: \"direct main\"\n"
                "    description:\n"
                "      name: sample_package\n"
                "      url: \"https://pub.dev\"\n"
                "    source: hosted\n"
                "    version: \"1.0.0\"\n"
            )
            (root / "third_party/pdfium_dart").mkdir(parents=True)
            (root / "third_party/pdfium_dart/LICENSE").write_text("MIT License\n")
            result = readiness.check_licences(root)
            self.assertTrue(
                any("sample_package" in failure for failure in result.failures),
                result.failures,
            )

    def test_combined_notice_header_covers_resolved_package(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            licences = root / "docs/implementation/licenses"
            licences.mkdir(parents=True)
            (root / "LICENSE").write_text("MIT License\n")
            (root / "pubspec.yaml").write_text(
                "dependencies:\n  flutter:\n    sdk: flutter\n"
            )
            (root / "pubspec.lock").write_text(
                "packages:\n"
                "  sample_package:\n"
                "    dependency: \"direct main\"\n"
                "    description:\n"
                "      name: sample_package\n"
                "      url: \"https://pub.dev\"\n"
                "    source: hosted\n"
                "    version: \"1.0.0\"\n"
            )
            (licences / "16-adopted-package-NOTICES.txt").write_text(
                "===== sample_package 1.0.0: LICENSE =====\nMIT License\n"
            )
            (licences / "pdfium-8100-NOTICES.txt").write_text("notices\n")
            (licences / "sqlite3mc-2.6.1-THIRD_PARTY_NOTICES.txt").write_text("notices\n")
            (root / "third_party/pdfium_dart").mkdir(parents=True)
            (root / "third_party/pdfium_dart/LICENSE").write_text("MIT License\n")
            audit_directory = root / 'tool/release'
            audit_directory.mkdir(parents=True)
            notice = licences / '16-adopted-package-NOTICES.txt'
            (audit_directory / 'package_licences.json').write_text(json.dumps({
                'packages': [{'name': 'sample_package', 'version': '1.0.0',
                              'notice': str(notice.relative_to(root)),
                              'noticeSha256': hashlib.sha256(notice.read_bytes()).hexdigest()}]
            }))
            result = readiness.check_licences(root)
            self.assertEqual(result.failures, [])
            lock = root / 'pubspec.lock'
            lock.write_text(lock.read_text().replace('1.0.0', '1.0.1'))
            result = readiness.check_licences(root)
            self.assertTrue(any('exact version sample_package 1.0.1' in failure
                                for failure in result.failures), result.failures)


class ObligationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.data = json.loads((ROOT / "tool/release/obligations.json").read_text())

    def test_repository_obligations_are_complete(self) -> None:
        result = readiness.validate_obligations(ROOT, self.data)
        self.assertEqual(result.failures, [])

    def test_missing_story_fails(self) -> None:
        data = copy.deepcopy(self.data)
        data["stories"].pop()
        result = readiness.validate_obligations(ROOT, data)
        self.assertTrue(any("does not cover exactly" in failure for failure in result.failures))

    def test_host_tested_story_needs_existing_test(self) -> None:
        data = copy.deepcopy(self.data)
        data["stories"][0]["tests"] = ["test/release/does_not_exist_test.dart"]
        result = readiness.validate_obligations(ROOT, data)
        self.assertTrue(any("missing test path" in failure for failure in result.failures))

    def test_planned_screen_may_not_have_a_route(self) -> None:
        data = copy.deepcopy(self.data)
        screen = next(item for item in data["screens"] if item["id"] == "S18")
        screen["state"] = "planned"
        screen["route"] = "/reports"
        result = readiness.validate_obligations(ROOT, data)
        self.assertTrue(any("planned but declares a route" in failure for failure in result.failures))

    def test_passed_gate_requires_evidence_and_reviewer(self) -> None:
        data = copy.deepcopy(self.data)
        data["gates"][0]["status"] = "passed"
        result = readiness.validate_obligations(ROOT, data)
        self.assertTrue(any("no evidence" in failure for failure in result.failures))
        self.assertTrue(any("without a reviewer" in failure for failure in result.failures))


class ReleaseMetadataTest(unittest.TestCase):
    def test_repository_metadata_is_truthful(self) -> None:
        result = readiness.check_release_metadata(ROOT)
        self.assertEqual(result.failures, [])


if __name__ == "__main__":
    unittest.main()
