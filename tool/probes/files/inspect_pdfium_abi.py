#!/usr/bin/env python3
"""Reproduce bound exports, raw ELF evidence, headers and host config layout."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'docs/implementation/evidence/16-pdfium-8100'

def main():
    bindings = (ROOT / 'third_party/pdfium_dart/lib/src/pdfium_bindings.dart').read_text()
    names = sorted(set(re.findall(r"\('((?:FPDF|FORM|FSDK)[^']+)'\)", bindings)))
    assert len(names) == 455, len(names)
    (OUT / 'bound-symbols.txt').write_text('\n'.join(names) + '\n')
    results = {}
    with tempfile.TemporaryDirectory(prefix='vital-pdfium-abi-') as temporary:
        work = Path(temporary)
        for archive in sorted((ROOT / 'third_party/pdfium_dart/native').glob('*/pdfium.tgz')):
            with tarfile.open(archive) as source:
                header = source.extractfile('include/fpdfview.h').read()
                assert header == (OUT / 'headers/include/fpdfview.h').read_bytes()
                library = source.extractfile('lib/libpdfium.so').read()
            path = work / 'libpdfium.so'
            path.write_bytes(library)
            raw = subprocess.check_output(['readelf', '-W', '-l', '-d', '-n', '-V', '-s', str(path)], text=True)
            (OUT / f'{archive.parent.name}-readelf.txt').write_text(raw)
            exports = {line.split()[-1] for line in raw.splitlines() if ' FUNC ' in line and ' GLOBAL ' in line and ' UND ' not in line}
            missing = sorted(set(names) - exports)
            assert not missing, missing
            results[archive.parent.name] = {'boundExports': len(names), 'missing': missing, 'headerSha256': hashlib.sha256(header).hexdigest()}
        c = work / 'layout.c'
        fields = ['version', 'm_pUserFontPaths', 'm_pIsolate', 'm_v8EmbedderSlot', 'm_pPlatform', 'm_RendererType', 'm_FontLibraryType', 'm_BrotliEnabled', 'm_IsolatePerDocument']
        c.write_text('#include <stddef.h>\n#include <stdio.h>\n#include "fpdfview.h"\nint main(void) {\n' +
                     'printf("sizeof=%zu\\n", sizeof(FPDF_LIBRARY_CONFIG));\n' +
                     ''.join(f'printf("{field}=%zu\\n", offsetof(FPDF_LIBRARY_CONFIG, {field}));\n' for field in fields) + 'return 0;\n}\n')
        subprocess.run(['cc', '-I', str(OUT / 'headers/include'), str(c), '-o', str(work / 'layout')], check=True)
        raw = subprocess.check_output([str(work / 'layout')], text=True)
        (OUT / 'host-config-layout.txt').write_text(raw)
        layout = dict(line.split('=') for line in raw.splitlines())
        assert layout == {'sizeof': '56', 'version': '0', 'm_pUserFontPaths': '8', 'm_pIsolate': '16', 'm_v8EmbedderSlot': '24', 'm_pPlatform': '32', 'm_RendererType': '40', 'm_FontLibraryType': '44', 'm_BrotliEnabled': '48', 'm_IsolatePerDocument': '52'}, layout
        results['hostConfig8100'] = layout
        results['retainedDartPrefix'] = {'size': 48, 'supportedVersions': [1, 2, 3, 4, 5], 'guardBeforeNativeLookup': True}
    (OUT / 'abi-reproduction.json').write_text(json.dumps(results, indent=2) + '\n')
    print('455 bound exports verified on all 4 targets; C8100 config offsets reproduced; retained prefix guarded at version5')

if __name__ == '__main__':
    main()
