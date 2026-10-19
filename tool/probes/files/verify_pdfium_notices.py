#!/usr/bin/env python3
"""Verify the shipped notice union against every admitted, pinned archive."""
from pathlib import Path
import hashlib
import json
import tarfile

ROOT = Path(__file__).resolve().parents[3]

def main():
    union = {}
    targets = {}
    for archive in sorted((ROOT / 'third_party/pdfium_dart/native').glob('*/pdfium.tgz')):
        names = []
        with tarfile.open(archive) as source:
            for member in source.getmembers():
                if not member.isfile() or not (member.name == 'LICENSE' or member.name.startswith('licenses/')):
                    continue
                data = source.extractfile(member).read()
                assert member.name not in union or union[member.name] == data, member.name
                union[member.name] = data
                names.append(member.name)
        targets[archive.parent.name] = sorted(names)
    aggregate = (ROOT / 'docs/implementation/licenses/pdfium-8100-NOTICES.txt').read_text()
    for name, data in union.items():
        for directory in ['docs/implementation/licenses/pdfium-8100', 'docs/implementation/evidence/16-pdfium-8100']:
            assert (ROOT / directory / name).read_bytes() == data, (directory, name)
        try:
            text = data.decode('utf-8')
        except UnicodeDecodeError:
            text = data.decode('latin-1')
        assert f'===== {name} =====\n{text.rstrip()}\n' in aggregate, name
    # The exact aggregate is declared in the application's shipped asset directory.
    assert 'docs/implementation/licenses/' in (ROOT / 'pubspec.yaml').read_text()
    evidence = {'targets': targets, 'unionCountIncludingRoot': len(union),
                'files': {name: hashlib.sha256(data).hexdigest() for name, data in sorted(union.items())},
                'aggregateSha256': hashlib.sha256(aggregate.encode()).hexdigest()}
    (ROOT / 'docs/implementation/evidence/16-pdfium-8100/notice-union.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(f'{len(targets)} targets: {len(union)} exact notice files present in distributable aggregate')

if __name__ == '__main__':
    main()
