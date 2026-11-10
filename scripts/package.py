#!/usr/bin/env python3
"""Create the small, self-contained experimental driver/diagnostic ZIP."""
import argparse
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
files = [(ROOT / 'README.TXT', 'README.TXT'), (ROOT / 'LICENSE', 'LICENSE')]
for f in sorted((ROOT / 'bin').iterdir()):
    files.append((f, ('DRIVERS/' if f.suffix == '.DRV' else '') + f.name))
for directory in ('src', 'diagnostics', 'tests', 'scripts', 'bin'):
    for f in sorted((ROOT / directory).rglob('*')):
        if f.is_file() and '__pycache__' not in f.parts and f.suffix != '.pyc':
            files.append((f, 'SOURCE/' + f.relative_to(ROOT).as_posix()))
files.append((ROOT / 'README.md', 'SOURCE/README.md'))
files.append((ROOT / 'README.TXT', 'SOURCE/README.TXT'))
files.append((ROOT / 'LICENSE', 'SOURCE/LICENSE'))
a.out.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(a.out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for path, name in files:
        z.write(path, 'WHEEL01/' + name)
with zipfile.ZipFile(a.out) as z:
    assert z.testzip() is None
    assert len(z.namelist()) == len(set(z.namelist()))
    assert all(not n.startswith('/') and '..' not in n.split('/') for n in z.namelist())
print('Created %s: %d files, %d bytes' % (a.out, len(files), a.out.stat().st_size))
