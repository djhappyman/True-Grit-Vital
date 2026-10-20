#!/usr/bin/env python3
"""Bundle admitted notices, including exact hosted LICENSE files after pub get."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import unquote, urlparse


def build(root: Path) -> bytes:
    audit = json.loads((root / 'tool/release/package_licences.json').read_text())
    config_path = root / '.dart_tool/package_config.json'
    config = json.loads(config_path.read_text())
    package_paths = {}
    for package in config['packages']:
        uri = package['rootUri']
        parsed = urlparse(uri)
        package_paths[package['name']] = (
            Path(unquote(parsed.path)) if parsed.scheme == 'file'
            else (config_path.parent / unquote(uri)).resolve()
        )
    sections = []
    seen = set()
    for package in audit['packages']:
        raw = (package_paths[package['name']] / 'LICENSE').read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        if digest != package['licenceTextSha256']:
            raise ValueError(f"Cached LICENSE differs for {package['name']} {package['version']}")
        title = f"{package['name']} {package['version']}: LICENSE"
        sections.append(f'===== {title} =====\n'.encode() + raw + b'\n\n')
        seen.add(digest)
    # Retain additional notices for native libraries, bundled fonts, Flutter
    # and package subcomponents. Never include archives or implementation notes.
    for path in sorted((root / 'docs/implementation/licenses').rglob('*')):
        if not path.is_file() or not ('LICENSE' in path.name or path.suffix == '.txt'):
            continue
        raw = path.read_bytes()
        try:
            text = raw.decode('utf-8')
        except UnicodeDecodeError:
            # The retained FreeType notice uses Latin-1 copyright symbols.
            if path.name != 'freetype.txt':
                raise
            text = raw.decode('latin-1')
        digest = hashlib.sha256(raw).hexdigest()
        if digest in seen:
            continue
        seen.add(digest)
        title = path.name if path.parent == root / 'docs/implementation/licenses' else f'{path.parent.name}: {path.name}'
        sections.append(f'===== {title} =====\n'.encode() + text.encode('utf-8') + b'\n\n')
    result = b''.join(sections)
    if len(result) > 4 * 1024 * 1024:
        raise ValueError('Notices exceed the bounded reader size')
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    destination = root / 'assets/legal/notices.txt'
    result = build(root)
    if args.check:
        if not destination.is_file() or destination.read_bytes() != result:
            raise SystemExit('Bundled notices are stale; run python3 tool/release/build_notices.py')
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(result)
    print(f'Bundled notices verified: {len(result)} bytes')


if __name__ == '__main__':
    main()
