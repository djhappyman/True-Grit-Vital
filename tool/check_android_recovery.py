#!/usr/bin/env python3
"""Exercise reversible missing-file failures only on Vital's synthetic AVD."""
import json
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
ADB = Path(os.environ.get('ANDROID_HOME', str(Path.home() / 'Android/Sdk'))) / 'platform-tools/adb'
SERIAL = 'emulator-5556'
PACKAGE = 'dev.truegrit.vital'
EVIDENCE = ROOT / 'docs/implementation/evidence/02-emulator'


def adb(*args):
    return subprocess.run([str(ADB), '-s', SERIAL, *args], check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30).stdout


def app(*args):
    return adb('shell', 'run-as', PACKAGE, *args)


def wait_label(label, artifact):
    for _ in range(8):
        adb('shell', 'uiautomator', 'dump', '/data/local/tmp/vital-recovery-ui.xml')
        xml = adb('shell', 'cat', '/data/local/tmp/vital-recovery-ui.xml')
        nodes = ET.fromstring(xml).iter('node')
        if any(label in (n.get('text', ''), n.get('content-desc', '')) for n in nodes):
            (EVIDENCE / f'{artifact}.xml').write_bytes(xml)
            (EVIDENCE / f'{artifact}.png').write_bytes(adb('exec-out', 'screencap', '-p'))
            return
    raise RuntimeError(f'Expected screen did not appear: {label}')


def start():
    adb('shell', 'am', 'start', '-W', '-n', f'{PACKAGE}/.MainActivity')


def stop():
    adb('shell', 'am', 'force-stop', PACKAGE)


def main():
    if adb('emu', 'avd', 'name').decode().splitlines()[0] != 'vital_api36':
        raise RuntimeError('Only the dedicated synthetic vital_api36 AVD is allowed')
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    results = []
    for filename in ('key-envelope.json', 'records.sqlite'):
        stop()
        path = f'no_backup/vital/{filename}'
        saved = f'{path}.recovery-test-original'
        # Refuse to replace recovery material left by an earlier interrupted run.
        existing = app('ls', 'no_backup/vital').decode().splitlines()
        if Path(saved).name in existing:
            raise RuntimeError('Prior recovery source exists; preserve it for inspection')
        before = app('sha256sum', path).decode().split()[0]
        app('mv', path, saved)
        try:
            start()
            wait_label('Records unavailable', f'missing-{filename}')
            after = app('sha256sum', saved).decode().split()[0]
            names = app('ls', 'no_backup/vital').decode().splitlines()
            assert filename not in names, 'Missing file was silently recreated'
            assert before == after, 'Preserved source changed'
        finally:
            stop()
            app('mv', saved, path)
        start()
        wait_label('Today', f'restored-{filename}')
        results.append({'missing': filename, 'recovery_visible': True,
                        'no_replacement': True, 'original_hash_preserved': before == after,
                        'normal_launch_after_restore': True})
    adb('shell', 'rm', '/data/local/tmp/vital-recovery-ui.xml')
    (EVIDENCE / 'recovery-results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()
