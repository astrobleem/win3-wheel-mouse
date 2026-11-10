#!/usr/bin/env python3
"""Validate the committed driver images and the source/runtime contract."""
from pathlib import Path
from check_image import inspect_image

ROOT = Path(__file__).resolve().parents[1]
for name in ('WHEEL', 'WDOS', 'WCOM1', 'WCOM2'):
    result = inspect_image((ROOT / 'bin' / (name + '.DRV')).read_bytes())
    print(name + ': ' + result['status'])
for name in ('WHEELCHK.EXE', 'WDIAG.EXE'):
    assert (ROOT / 'bin' / name).read_bytes()[:2] == b'MZ', name
# Catch regression of the nonzero DI serial Mouse_Event argument.
src = (ROOT / 'src/driver.asm').read_text()
assert 'xor si,si\n push di\n xor di,di\n push ds\n call dword ptr callback' in src
assert 'cmp ax,0ffffh\n je detect_unknown\n cmp bx,0626h' in (ROOT / 'src/dos33.asm').read_text()
for p in ROOT.rglob('*'):
    if '.git' in p.parts or not p.is_file():
        continue
    if p.suffix.upper() in ('.ASM', '.BAT', '.C', '.DEF', '.LNK'):
        assert b'\n' not in p.read_bytes().replace(b'\r\n', b''), str(p)
print('Runtime/source checks: PASS')
