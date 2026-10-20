#!/usr/bin/env python3
import pathlib, shutil, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parents[2]
version = (root / '.flutter-version').read_text().strip()
dart = pathlib.Path.home() / f'.local/share/flutter-{version}/bin/dart'
steps = 0
directory = tempfile.mkdtemp(prefix='vital-backup-process-')
try:
    def run(mode, expected=0):
        global steps
        result = subprocess.run(
            [str(dart), 'run', str(root / 'test/backup/backup_process.dart'), directory, mode],
            cwd=root,
            text=True,
            capture_output=True,
            timeout=120,
        )
        if result.returncode != expected:
            raise RuntimeError(f'{mode}: {result.returncode}\n{result.stdout}\n{result.stderr}')
        print(result.stdout.strip() or f'PASS backup {mode} expected-exit={expected}', flush=True)
        steps += 1

    run('init')
    run('interrupt', 90)
    partial = list(pathlib.Path(directory, 'staging').glob('backup-*.vitalbackup'))
    if not partial:
        raise RuntimeError('interrupted archive was not left for cleanup evidence')
    print(f'PASS interrupted archive present: {partial[0].name}', flush=True)
    run('cleanup')
    run('verify')
finally:
    shutil.rmtree(directory)
print(f'PASS backup interruption process / {steps} steps', flush=True)
