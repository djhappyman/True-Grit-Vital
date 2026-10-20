#!/usr/bin/env python3
"""Compile the pure artifact transfer tests with the project's cached Kotlin SDK.

No Gradle resolution, downloads, Android device or test dependency is needed.
The compiled class directory is task-owned and removed on success or failure.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
CACHE = Path(os.environ.get("GRADLE_USER_HOME", str(Path.home() / ".gradle"))) / "caches/modules-2/files-2.1"


def jar(group, artifact, version):
    found = list((CACHE / group / artifact / version).glob("*/*.jar"))
    if len(found) != 1:
        raise RuntimeError(f"Expected cached {artifact} {version}; build the admitted Android toolchain first")
    return str(found[0])


def main():
    settings = (ROOT / "android/settings.gradle.kts").read_text()
    version = re.search(r'id\("org.jetbrains.kotlin.android"\) version "([^"]+)"', settings).group(1)
    stdlib = jar("org.jetbrains.kotlin", "kotlin-stdlib", version)
    compiler = [jar("org.jetbrains.kotlin", artifact, version) for artifact in
                ["kotlin-compiler-embeddable", "kotlin-build-tools-api", "kotlin-script-runtime", "kotlin-daemon-embeddable"]]
    compiler.extend([stdlib, jar("org.jetbrains.kotlin", "kotlin-reflect", "1.6.10"),
                     jar("org.jetbrains.kotlinx", "kotlinx-coroutines-core-jvm", "1.8.0"),
                     jar("org.jetbrains", "annotations", "13.0")])
    with tempfile.TemporaryDirectory(prefix="vital-artifact-jvm-") as classes:
        subprocess.run(["java", "-cp", os.pathsep.join(compiler), "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler",
                        "-no-stdlib", "-no-reflect", "-jvm-target", "17", "-classpath", stdlib,
                        "-d", classes,
                        str(ROOT / "android/app/src/main/kotlin/dev/truegrit/vital/AttachmentHandoffFiles.kt"),
                        str(ROOT / "android/app/src/main/kotlin/dev/truegrit/vital/ArtifactTransferFiles.kt"),
                        str(ROOT / "android/app/src/test/kotlin/dev/truegrit/vital/ArtifactTransferFilesTest.kt")], check=True)
        subprocess.run(["java", "-cp", os.pathsep.join([classes, stdlib]),
                        "dev.truegrit.vital.ArtifactTransferFilesTestKt"], check=True)


if __name__ == "__main__":
    main()
