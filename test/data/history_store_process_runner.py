"""Check encrypted history recovery in separate Dart processes."""

import os
import pathlib
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
version = (root / '.flutter-version').read_text().strip()
data_root = pathlib.Path(os.environ.get('XDG_DATA_HOME') or pathlib.Path.home() / '.local/share')
sdk_root = pathlib.Path(os.environ.get('VITAL_FLUTTER_SDK') or data_root / f'flutter-{version}')
dart = sdk_root / 'bin/dart'

for modes in [('init', 'before', 'verify-old', 'verify-retry'), ('init', 'after', 'verify-retry')]:
    directory = tempfile.mkdtemp(prefix='vital-history-process-')
    try:
        for mode in modes:
            result = subprocess.run(
                [str(dart), 'run', str(root / 'test/data/history_store_process.dart'), directory, mode],
                cwd=root,
                text=True,
                capture_output=True,
                timeout=120,
            )
            expected = 91 if mode == 'before' else 92 if mode == 'after' else 0
            if result.returncode != expected:
                raise RuntimeError(
                    f'{mode}: expected exit {expected}, got {result.returncode}\n'
                    f'{result.stdout[-4000:]}\n{result.stderr[-4000:]}'
                )
            print(result.stdout.strip() or f'PASS history {mode} expected-exit={expected}', flush=True)
    finally:
        # Only this runner's invented, disposable dataset is removed.
        shutil.rmtree(directory)

# Crash after ALTER, after backfill, and after the complete schema/version step.
# Then retry through the actual Drift migration; also crash after its commit.
for modes in [
    ('init', 'before-1', 'verify-old-retry'),
    ('init', 'before-2', 'verify-old-retry'),
    ('init', 'before-7', 'verify-old-retry'),
    ('init', 'after', 'verify'),
]:
    directory = tempfile.mkdtemp(prefix='vital-history-migration-')
    try:
        for mode in modes:
            result = subprocess.run(
                [str(dart), 'run', str(root / 'test/data/history_migration_process.dart'), directory, mode],
                cwd=root, text=True, capture_output=True, timeout=120,
            )
            expected = 91 if mode.startswith('before-') else 92 if mode == 'after' else 0
            if result.returncode != expected:
                raise RuntimeError(
                    f'migration {mode}: expected {expected}, got {result.returncode}\n'
                    f'{result.stdout[-4000:]}\n{result.stderr[-4000:]}'
                )
            print(result.stdout.strip() or f'PASS history schema18 {mode} expected-exit={expected}', flush=True)
    finally:
        shutil.rmtree(directory)
