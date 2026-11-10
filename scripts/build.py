#!/usr/bin/env python3
"""Build with separately supplied MASM/C6 tools and run emulator-only tests."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--dosbox', required=True)
p.add_argument('--toolchain', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
tools = a.toolchain.resolve()
out = a.out.resolve()
for path in (tools, out):
    if any(c in str(path) for c in ('"', '\r', '\n')):
        p.error('Paths must not contain quotes or line breaks')
if out.exists():
    p.error('--out must be a new directory; existing output is never erased')
for name in ('BIN/MASM.EXE', 'BIN/LINK4.EXE', 'BIN/CL.EXE', 'LIB/SLIBCEW.LIB', 'LIB/LIBW.LIB'):
    if not (tools / name).is_file():
        p.error('Missing toolchain input: ' + name)
out.mkdir(parents=True)
for directory in ('src', 'tests/driver', 'diagnostics/windows'):
    for f in (ROOT / directory).iterdir():
        if f.is_file() and f.name != 'BUILD.BAT':
            shutil.copy2(f, out / f.name)
shutil.copy2(ROOT / 'diagnostics/dos/WHEELCHK.ASM', out / 'WHEELCHK.ASM')
shutil.copytree(ROOT / 'tests/diagnostic', out / 'QA')
# Same driver implementation, only omit its DLL loader entry in the DOS link.
core = 'TRANSPORT equ 4\n' + (out / 'driver.asm').read_text().replace('end LibMain', 'end')
(out / 'DCORE.ASM').write_bytes(core.replace('\n', '\r\n').encode('ascii'))
(out / 'PCORE.ASM').write_bytes(core.replace('TRANSPORT equ 4', 'TRANSPORT equ 3').replace('\n', '\r\n').encode('ascii'))
subprocess.run([sys.executable, str(ROOT / 'tests/make_vectors.py'),
                '--output', str(out / 'VECTORS.BIN'), '--overflow-events', '65566'], check=True)
commands = ['@echo off', 'PATH=C:\\BIN;Z:\\',
            'SET INCLUDE=C:\\DDK\\286\\INC;C:\\INCLUDE', 'SET LIB=C:\\LIB']
def run(command):
    commands.extend([command + ' >> BUILD.LOG', 'IF ERRORLEVEL 1 GOTO FAIL'])
for name in ('driver', 'decoder', 'TIMESTMP', 'dos33', 'ps2', 'WPS2', 'WDOS', 'WCOM1', 'WCOM2', 'DCORE', 'PCORE', 'NATIVE', 'PS2TEST', 'PS2HW', 'PS2FAIL', 'PS2MISS', 'dostest'):
    run('MASM /ML %s,%s,%s;' % (name, name, name))
for name in ('WHEEL', 'WDOS', 'WCOM1', 'WCOM2', 'WPS2', 'NATIVE', 'PS2TEST', 'PS2HW', 'PS2FAIL', 'PS2MISS', 'DTEST'):
    run('LINK4 /NOE /NOD @' + name + '.LNK')
run('MASM WHEELCHK.ASM,WHEELCHK.OBJ,WHEELCHK.LST,NUL;')
run('LINK4 WHEELCHK.OBJ,WHEELCHK.EXE,WHEELCHK.MAP,,;')
run('CL /nologo /c /G0 /Gw /AS /W3 /Od WDIAG.C')
run('LINK4 /NOE /NOD @WDIAG.LNK')
commands += ['NATIVE > NATIVE.LOG', 'IF ERRORLEVEL 1 GOTO FAIL',
             'PS2TEST > PS2TEST.LOG', 'IF ERRORLEVEL 1 GOTO FAIL',
             'DTEST > DTEST.LOG', 'IF ERRORLEVEL 1 GOTO FAIL', 'CD QA']
run('MASM MOCK33.ASM,MOCK33.OBJ,MOCK33.LST,NUL;')
run('LINK4 MOCK33.OBJ,MOCK33.EXE,MOCK33.MAP,,;')
commands += ['CD ..', 'ECHO PASS > RESULT.LOG', 'GOTO END', ':FAIL',
             'ECHO FAIL > RESULT.LOG', ':END', 'EXIT']
(out / 'BUILD.BAT').write_bytes(('\r\n'.join(commands) + '\r\n').encode('ascii'))
config = '''[sdl]
fullscreen=false
output=surface
[dosbox]
machine=tandy
memsize=0
memsizekb=640
allow more than 640kb base memory=false
[cpu]
core=normal
cputype=8086_prefetch
cycles=fixed 200000
fpu=false
[dos]
xms=false
ems=false
umb=false
[mixer]
nosound=true
[midi]
mididevice=none
[serial]
serial1=dummy
serial2=dummy
[autoexec]
@echo off
mount C "%s"
mount D "%s"
D:
%%s
''' % (tools, out)
env = os.environ.copy()
env.setdefault('SDL_VIDEODRIVER', 'dummy')
env.setdefault('SDL_AUDIODRIVER', 'dummy')
def session(name, command, template=config):
    cnf = out / (name + '.CNF')
    cnf.write_text(template % command)
    with (out / (name + '-host.log')).open('w') as log:
        subprocess.run([a.dosbox, '-defaultconf', '-conf', str(cnf)], env=env,
                       stdout=log, stderr=subprocess.STDOUT, timeout=240, check=True)
session('BUILD', 'BUILD.BAT')
if (out / 'RESULT.LOG').read_text().strip() != 'PASS':
    raise SystemExit('Build/native check failed; inspect BUILD.LOG and NATIVE.LOG')
# The hardware fixtures own a disposable emulated AT controller. DOSBox-X's
# disabled INT33 option can leave a non-IRET stub, so each fixture temporarily
# saves/clears/restores that vector itself. No installed DOS mouse is invoked.
ps2config = config.replace('machine=tandy', 'machine=svga_s3').replace(
    '[dos]\n', '[keyboard]\ncontrollertype=at\naux=true\nauxdevice=DEVICE\n[dos]\nint33=false\n')
for device, tag in (('2button', 'PS2STD'), ('3button', 'PS2THR'),
                    ('intellimouse', 'PS2WHL'), ('intellimouse45', 'PS2EXP')):
    session(tag, 'PS2HW > ' + tag + '.LOG\nEXIT',
            ps2config.replace('DEVICE', device))
    assert (out / (tag + '.LOG')).read_text().startswith('PASS PS2 hardware'), tag
session('PS2FAIL', 'PS2FAIL > PS2FAIL.LOG\nEXIT',
        ps2config.replace('DEVICE', 'intellimouse'))
assert (out / 'PS2FAIL.LOG').read_text().startswith('PASS PS2 refusal')
for name, template in (('PS2NONE', ps2config.replace('DEVICE', 'none')),
                       ('PS2NOAX', ps2config.replace('DEVICE', 'none').replace('aux=true', 'aux=false'))):
    session(name, 'PS2MISS > ' + name + '.LOG\nEXIT', template)
    assert (out / (name + '.LOG')).read_text().startswith('PASS PS2 missing'), name
session('PS2NOACK', 'PS2MISS /FORCE > PS2NOACK.LOG\nEXIT',
        ps2config.replace('DEVICE', 'none'))
assert (out / 'PS2NOACK.LOG').read_text().startswith('PASS PS2 missing')
assert (out / 'PS2TEST.LOG').read_text().strip() == 'PASS PS2 decoder checks 2289'
subprocess.run([sys.executable, str(out / 'QA/MKCOM.PY')], check=True)
session('PROBE', 'CD QA\nCALL SUITE.BAT\nEXIT')
assert (out / 'QA/RESULT.LOG').read_text().strip() == 'PASS'
wheel = (out / 'QA/WHEEL.LOG').read_text()
for sample in ('+1', '-1', '+127', '-128'):
    assert 'Wheel delta: ' + sample + '\n' in wheel
assert '0004' in wheel
sys.path.insert(0, str(ROOT / 'scripts'))
from check_image import inspect_image
for name in ('WHEEL', 'WDOS', 'WCOM1', 'WCOM2', 'WPS2'):
    inspect_image((out / (name + '.DRV')).read_bytes())
assert (out / 'NATIVE.LOG').read_text().startswith('PASS native driver')
assert (out / 'DTEST.LOG').read_text().startswith('PASS records ')
print('Build, decoders, UART/IRQ4, PS/2 controller/IRQ12, refusals, DOS callbacks, diagnostics and image checks: PASS')
print('Windows and real-hardware acceptance are separate checks.')
