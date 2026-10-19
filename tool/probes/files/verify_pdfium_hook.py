#!/usr/bin/env python3
"""Exercise the reviewed native hook with isolated synthetic outputs, never live caches."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
# The host SDK path is supplied by the same pinned project wrapper convention.
SDK_VERSION = (ROOT / '.flutter-version').read_text().strip()
DART = Path(os.environ.get('VITAL_FLUTTER_SDK', str(Path.home() / '.local/share' / f'flutter-{SDK_VERSION}'))) / 'bin/dart'


def main():
    results = []
    with tempfile.TemporaryDirectory(prefix='vital-pdfium-hook-probe-') as task:
        base = Path(task)
        package = ROOT / 'third_party/pdfium_dart'
        config = {
            'assets': {},
            'config': {'build_asset_types': ['code_assets/code'], 'extensions': {'code_assets': {
                'link_mode_preference': 'dynamic', 'target_architecture': 'x64', 'target_os': 'linux'}},
                'linking_enabled': False},
            'out_dir_shared': str(base / 'output') + '/',
            'out_file': str(base / 'result.json'), 'package_name': 'pdfium_dart',
            'package_root': str(package) + '/', 'user_defines': {},
        }

        def run(name, expected, message=None):
            path = base / 'input.json'
            path.write_text(json.dumps(config))
            result = subprocess.run([str(DART), f'--packages={ROOT / ".dart_tool/package_config.json"}',
                                     str(package / 'hook/build.dart'), f'--config={path}'],
                                    cwd=ROOT, capture_output=True, text=True, timeout=60)
            assert (result.returncode == 0) == expected, (name, result.stdout, result.stderr)
            if message:
                assert message in result.stderr, (name, result.stderr)
            results.append({'case': name, 'exitCode': result.returncode, 'expectedSuccess': expected})

        run('verified offline archive produces admitted native asset', True)
        run('unchanged cached native asset is verified again', True)
        cached = base / 'output/chromium_8100/linux-x64/libpdfium.so'
        original = cached.read_bytes()
        cached.write_bytes(b'X' + original[1:])
        run('corrupt cached native asset fails closed', False, 'cached library integrity mismatch')
        copied = base / 'package/native/linux-x64'
        copied.mkdir(parents=True)
        shutil.copyfile(package / 'native/manifest.json', base / 'package/native/manifest.json')
        shutil.copyfile(package / 'native/linux-x64/pdfium.tgz', copied / 'pdfium.tgz')
        config['package_root'] = str(base / 'package') + '/'
        config['out_dir_shared'] = str(base / 'other-output') + '/'
        archive = copied / 'pdfium.tgz'
        raw = archive.read_bytes()
        archive.write_bytes(b'X' + raw[1:])
        run('corrupt source archive fails closed', False, 'archive integrity mismatch')
        archive.write_bytes(raw)
        manifest = json.loads((base / 'package/native/manifest.json').read_text())
        manifest['assets']['linux-x64']['librarySha256'] = '0' * 64
        (base / 'package/native/manifest.json').write_text(json.dumps(manifest))
        run('unexpected extracted library fails closed', False, 'library integrity mismatch')
        config['config']['extensions']['code_assets']['target_os'] = 'windows'
        run('unadmitted platform has no fallback', False, 'no admitted binary')
    destination = ROOT / 'docs/implementation/evidence/16-pdfium-8100/hook-probe.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps({'cases': results, 'temporaryOutputsRemoved': True}, indent=2) + '\n')
    print(f'{len(results)} native hook integrity cases passed')


if __name__ == '__main__':
    main()
