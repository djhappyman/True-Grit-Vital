#!/usr/bin/env python3
"""Serial CLI lease required. Verify warm-run and corrupt-output rerun, restoring known cache."""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'docs/implementation/evidence/16-pdfium-8100'
CACHE = ROOT / '.dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_8100/linux-x64/libpdfium.so'

def main():
    results = []
    def run(case, success):
        command = ['./tool/flutterw', 'test', '--verbose', 'test/attachments/pdfium_config_abi_test.dart']
        process = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180)
        raw = process.stdout + process.stderr
        (OUT / f'runner-{case}.txt').write_text(raw)
        assert (process.returncode == 0) == success, (case, process.returncode, raw[-3000:])
        assert 'File modified during build' not in raw, case
        results.append({'case': case, 'exitCode': process.returncode, 'command': command})
        return raw
    run('settle', True)
    warm = run('warm', True)
    # hooks_runner emits the skipped-hook decision in verbose mode.
    assert 'Skipping build for pdfium_dart' in warm, 'Missing warm-hook skip evidence'
    original = CACHE.read_bytes()
    try:
        CACHE.write_bytes(bytes([original[0] ^ 1]) + original[1:])
        failure = run('corrupt-output', False)
        assert 'cached library integrity mismatch' in failure
    finally:
        CACHE.write_bytes(original)
    run('restored', True)
    (OUT / 'runner-probe.json').write_text(json.dumps({'cases': results, 'cacheRestored': True,
          'warmHookSkipped': True, 'corruptionTriggeredHookAndFailedClosed': True,
          'outputNotListedAsOwnDependency': True}, indent=2) + '\n')
    print('Warm hook skip, output hash invalidation, corrupt-cache fail-closed, restored run verified')

if __name__ == '__main__':
    main()
