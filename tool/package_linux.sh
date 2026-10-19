#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$project_root"
case "${1:-build}" in
  build) ./tool/flutterw build linux --release --no-pub ;;
  --existing) ;;
  *) printf 'Usage: tool/package_linux.sh [build|--existing]\n' >&2; exit 2 ;;
esac

# Package only this project's verified bundle. Never install system integration.
python3 - "$project_root" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile

root = Path(sys.argv[1])
source = root / 'build/linux/x64/release/bundle'
destination = root / 'output/linux'
target = destination / 'true-grit-vital'
marker = '.vital-linux-package'
required = ['vital', 'lib/libapp.so', 'lib/libflutter_linux_gtk.so',
            'lib/libsqlite3mc.so', 'lib/libpdfium.so', 'data/icudtl.dat', 'data/flutter_assets/NOTICES.Z']
for name in required:
    if not (source / name).is_file() or (source / name).stat().st_size == 0:
        raise SystemExit(f'Missing release bundle component: {name}')
if not os.access(source / 'vital', os.X_OK):
    raise SystemExit('The release executable is not executable')
if target.exists() and (not (target / marker).is_file()
                        or (target / marker).read_text() != 'true-grit-vital-linux-v1\n'):
    raise SystemExit('Refusing to replace an unrecognised output directory')
# Replacing an executable's libraries while it runs can break its current session.
for proc in Path('/proc').iterdir():
    if proc.name.isdecimal():
        try:
            executable = (proc / 'exe').resolve(strict=True)
            if executable == target / 'vital':
                raise SystemExit('Close the packaged Vital app before packaging again')
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass

destination.mkdir(parents=True, exist_ok=True)
stage = Path(tempfile.mkdtemp(prefix='.vital-package-', dir=destination))
try:
    packaged = stage / target.name
    shutil.copytree(source, packaged)
    dependencies = []
    for binary in [packaged / 'vital', *sorted((packaged / 'lib').rglob('*.so'))]:
        result = subprocess.run(['ldd', str(binary)], text=True, capture_output=True)
        if result.returncode or 'not found' in result.stdout:
            raise SystemExit(f'Unresolved native dependencies for {binary.name}:\n'
                             f'{result.stdout}{result.stderr}')
        dependencies.append(f'[{binary.relative_to(packaged)}]\n{result.stdout}')
    (packaged / 'HOST-LIBRARIES.txt').write_text('\n'.join(dependencies))
    notices = packaged / 'licenses'
    shutil.copytree(root / 'docs/implementation/licenses', notices)
    (packaged / marker).write_text('true-grit-vital-linux-v1\n')
    launcher = packaged / 'launch'
    launcher.write_text('''#!/usr/bin/env bash
set -euo pipefail
bundle_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$bundle_root/vital" "$@"
''')
    launcher.chmod(0o755)
    (packaged / 'README.md').write_text('''# True Grit: Vital

Local development build for Linux x86-64 with adult profiles, recording and corrections, encrypted drafts, daily, calendar and interval plans, pauses and repeating breaks, phases, finite ends and one-off changes, personal substance types, exact container stock, ready-mixed products, combined logging, optional sites, events, recorded use periods and protected file/photo attachments with bounded PDF/image previews. It is not a complete release of the approved specification. Native reminders are not implemented in this build.

## Start

Open a terminal in this folder and run `./launch`. Keep this entire folder together. The executable needs the `lib` and `data` folders beside it.

Use a graphical Linux session with GTK 3, the system libraries listed in `HOST-LIBRARIES.txt`, and an unlocked desktop Secret Service keyring. Vital also needs the installed commands `/usr/bin/secret-tool` (libsecret), `/usr/bin/gdbus` (GLib), `/usr/bin/flock` (util-linux), and the coreutils commands `install`, `chmod`, `sync` and `cat`. Their source and licence details are in `licenses/linux-system-prerequisites.txt`. A missing or locked keyring prevents opening records. Vital does not create a plaintext replacement.

## Records

The encrypted dataset is separate from this folder, under `$XDG_DATA_HOME/true_grit_vital`, or `$HOME/.local/share/true_grit_vital` when XDG_DATA_HOME is unset. Its key is stored in the desktop keyring. Keep both intact. Moving or deleting either can prevent access to existing records. Portable protected backup is not implemented yet.

Close Vital before replacing this folder with a newer build. Existing data and keyring entries are not removed by the packaging script.

## Notices

`licenses/` contains the retained dependency and native SQLite3MC notices. Flutter's compiled notices are also present at `data/flutter_assets/NOTICES.Z`. The application code's public distribution licence remains a separate owner decision. This is a local build, not permission to publish it.
''')
    manifest = {}
    for file in sorted(packaged.rglob('*')):
        if file.is_file():
            manifest[str(file.relative_to(packaged))] = hashlib.sha256(file.read_bytes()).hexdigest()
    (packaged / 'SHA256SUMS.json').write_text(json.dumps(manifest, indent=2) + '\n')
    # Produce the complete archive before replacing any known previous package.
    archive = stage / 'true-grit-vital-linux-x64.tar.gz'
    with tarfile.open(archive, 'w:gz') as tar:
        tar.add(packaged, arcname=packaged.name)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum_file = stage / (archive.name + '.sha256')
    checksum_file.write_text(f'{checksum}  {archive.name}\n')
    if target.exists():
        shutil.rmtree(target)
    packaged.rename(target)
    for file in [archive, checksum_file]:
        file.replace(destination / file.name)
    print(f'Launch: {target / "launch"}')
    print(f'Archive: {destination / archive.name}')
    print(f'SHA-256: {checksum}')
finally:
    shutil.rmtree(stage)
PY
