import pathlib, subprocess, tempfile, shutil
root=pathlib.Path(__file__).resolve().parents[2]
version=(root/'.flutter-version').read_text().strip()
dart=pathlib.Path.home()/f'.local/share/flutter-{version}/bin/dart'
scenarios=[
 ('init','begin-before','verify-empty'),
 ('init','begin','chunk-before','verify-stage-empty'),
 ('init','begin','mid','verify-stage-partial'),
 ('init','begin','complete-before','verify-stage-complete','publish-before','verify-stage-complete'),
 ('init','begin','complete-before','publish-after','verify-ready'),
 ('init','begin','complete-before','publish-after','delete-before','verify-ready'),
 ('init','begin','complete-before','publish-after','delete-mid','verify-pinned-delete'),
 ('init','begin','complete-before','publish-after','delete-after','verify-gone'),
]
expected_codes={'begin-before':81,'chunk-before':82,'mid':83,'complete-before':84,'publish-before':85,'publish-after':86,'delete-before':87,'delete-mid':88,'delete-after':89}
steps=0
for modes in scenarios:
 directory=tempfile.mkdtemp(prefix='vital-attachment-process-')
 try:
  for mode in modes:
   result=subprocess.run([str(dart),'run',str(root/'test/data/attachment_store_process.dart'),directory,mode],cwd=root,text=True,capture_output=True,timeout=90)
   expected=expected_codes.get(mode,0)
   if result.returncode!=expected:raise RuntimeError(f'{mode}: {result.returncode}\n{result.stdout}\n{result.stderr}')
   print(result.stdout.strip() or f'PASS attachment {mode} expected-exit={expected}',flush=True)
   steps+=1
 finally:shutil.rmtree(directory)
print(f'PASS {len(scenarios)} attachment scenarios / {steps} steps',flush=True)
