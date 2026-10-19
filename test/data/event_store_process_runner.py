import pathlib, subprocess, tempfile, shutil
root=pathlib.Path(__file__).resolve().parents[2]
version=(root/'.flutter-version').read_text().strip()
dart=pathlib.Path.home()/f'.local/share/flutter-{version}/bin/dart'
for modes in [('init','before','verify-empty','verify-retry'),('init','after','verify-retry')]:
    directory=tempfile.mkdtemp(prefix='vital-event-process-')
    try:
        for mode in modes:
            result=subprocess.run([str(dart),"run",str(root/'test/data/event_store_process.dart'),directory,mode],cwd=root,text=True,capture_output=True)
            expected=73 if mode=='before' else 74 if mode=='after' else 0
            if result.returncode!=expected:raise RuntimeError(f'{mode}: {result.returncode}\n{result.stdout}\n{result.stderr}')
            print(result.stdout.strip() or f'PASS event {mode} expected-exit={expected}')
    finally:
        shutil.rmtree(directory)
