# Win3 Wheel Mouse

Experimental, first-party mouse driver for **Windows 3.0 real mode on an
8086/8088**. One Windows mouse and wheel interface, with direct serial and
DOS INT 33h input backends. This is not a promise that every mouse works.

[Download candidate 0.1 test ZIP](downloads/WHEEL01.ZIP).

The test ZIP is for trying the driver safely on a spare installation. It
contains only the driver variants, DOS and Windows diagnostics, source and
instructions. No Windows, DOS, firmware, compiler, SDK, emulator image or
third-party mouse driver is included.

## Choose the input path

- **WHEEL.DRV:** Auto. Use an existing compatible DOS mouse driver first;
  otherwise use direct COM1/IRQ4. An installed but unsupported DOS driver
  stops selection rather than stealing its UART.
- **WDOS.DRV:** DOS only. Recommended for PMMOUSE/PicoMEM experiments and for
  serial, PS/2 or other mice already handled by a DOS mouse driver.
- **WCOM1.DRV:** Explicit direct serial, COM1 at 03F8h, IRQ4.
- **WCOM2.DRV:** Explicit direct serial, COM2 at 02F8h, IRQ3.

All four files have internal module name MOUSE. Select ONE. COM selection is
by driver file, not an INI setting. COM3/4, arbitrary ports/IRQs, direct PS/2,
USB host drivers and Windows protected/enhanced modes are not implemented.
Windows 3.1/3.11 is not qualified.

Direct serial uses 1200 baud, 7 data bits, no parity, one stop bit. It decodes
Microsoft-compatible 3-byte motion/buttons and IntelliMouse-compatible
fourth-byte vertical wheel data. It reports two buttons; middle and extra
buttons are not forwarded. Do not load a DOS serial mouse driver, use a
modem or another serial device on the selected port, or share its IRQ with
an active device when choosing a direct serial build. No mouse presence or
wheel capability handshake is claimed: parser-ready is not detected hardware.

The DOS backend requires the Microsoft-compatible version query to report
6.26 or newer and a functioning callback exchange (INT 33h/AX=0014h).
Wheel support additionally requires the CuteMouse-compatible AX=0011h
signature AX=574Dh, CX bit 0, and signed BH wheel events on callback bit 7.
Movement uses cumulative callback SI/DI mickeys. No reset, coordinate-range
change or mickey-ratio change is made. The previous callback pair is restored
when Windows disables the driver. While Windows owns this backend, do not
run another program that consumes its motion counters or replaces its callback.

## PicoMEM and PMMOUSE

The upstream PicoMEM wheel path is still a blocker. This package does not
change PicoMEM firmware, BIOS or PMMOUSE, and cannot recover wheel deltas
that are not delivered by them. PMMOUSE compatibility and physical movement,
buttons and wheel delivery must be tested, not inferred from a version number.
Start with WDOS.DRV so absence or incompatibility does not fall back to COM1.
The discussion is https://github.com/FreddyVRetro/ISA-PicoMEM/issues/169 .

## First test, before changing Windows

1. Use plain DOS, not a Windows DOS box. Load the DOS mouse driver normally
   used by the hardware. For an explicit direct-serial test, reboot without
   that DOS driver before starting Windows instead.
2. For the DOS path, run WHEELCHK /Q and save its output:
   `WHEELCHK /Q > CAPS.TXT`. This queries capabilities without reading counters.
3. Run WHEELCHK without /Q and turn the wheel both ways. It polls for about
   30 seconds; any key exits. Save with `WHEELCHK > DOSWHEEL.TXT` if desired.
   Nonzero signed samples are stronger evidence than an advertised capability.
   Polling consumes wheel counts; do not run another wheel consumer at once.
4. A wheel-capability failure is not a pointer-driver failure. The Windows
   DOS backend can still offer movement and two buttons without wheel support.

WHEELCHK conservatively rejects null/IRET handlers, unavailable/failed
version queries and versions below 6.00 before issuing the wheel query.
The Windows DOS backend has the stricter 6.26 callback-exchange requirement.
Exit codes: 0 wheel advertised (not necessarily observed), 1 no usable
vector, 2 old/unavailable version, 3 no wheel capability, 4 invalid argument.

## Install on a backed-up Windows 3.0 real-mode installation

These are manual experimental-driver instructions, not an installer. Use a
spare copy first and keep a working keyboard/DOS boot route for recovery.
Examples assume Windows is in C:\WINDOWS and this package is C:\WHEEL01.
Adjust those paths for your machine. Do not copy four drivers over one name.

1. Exit Windows completely. Back up C:\WINDOWS\SYSTEM.INI to a NEW backup
   name, for example SYSWHL.BAK. If that backup already exists, use a different
   name; never overwrite your only recovery copy. Also back up any existing
   WHEEL.DRV separately before replacing it.
2. Copy the chosen driver from DRIVERS to C:\WINDOWS\WHEEL.DRV. For PicoMEM:
   `COPY C:\WHEEL01\DRIVERS\WDOS.DRV C:\WINDOWS\WHEEL.DRV`.
3. In SYSTEM.INI, change only mouse.drv under [boot] to `mouse.drv=WHEEL.DRV`.
   Preserve all other settings and sections. Do not change the display driver,
   keyboard driver, SYSTEM.DRV, WIN.INI or startup programs.
4. Start with `WIN /R`. Run C:\WHEEL01\WDIAG.EXE from Program Manager's
   File / Run. If the pointer does not work, the keyboard still lets you exit.
5. To roll back, exit Windows, restore the saved SYSTEM.INI and the saved
   WHEEL.DRV (if there was one), then reboot to restore the normal DOS driver.
   Do not remove an original mouse driver file.

Existing Windows XT users already set to WHEEL.DRV need only the backed-up
file replacement. Keep the existing Tandy memory-reservation launcher when
using a Tandy display driver; this package does not replace it.

## Windows diagnostic and useful observations

Stop the scrolling bridge first: run `WXTWHL /STOP` if it is present. Close TP
or any other program that reads the wheel API. Only one wheel consumer should
run at a time. WDIAG refuses to run alongside the recognized Windows XT bridge.

WDIAG displays the selected backend, last wheel delta, signed total, sample
count, lost chunks, and mouse-move/button-down messages received inside its
window. Test both wheel directions, movement, left/right clicks, closing and
reopening the diagnostic, and a full Windows exit/restart. Close with Alt+F4.
WDIAG.LOG is written in the program's working directory and is overwritten
by each run. Save/rename it between runs. /AUTO performs a short loaded-driver
smoke check and then exits Windows; it is for disposable emulator runs only.

A serial parser-ready status or DOS wheel-advertised status does not prove
that hardware sent wheel events. A zero-failure /AUTO run is not a physical
wheel test. For a useful report, include the computer/CPU, Windows and DOS
versions, mouse/adapter and DOS driver version, selected DRV file, CAPS.TXT,
DOSWHEEL.TXT, WDIAG.LOG and what physical actions did or did not work.

WDIAG is a test viewer, not a global scrolling bridge. Existing Windows XT
WXTWHL clients can use the preserved wheel API. The bridge and its paired TP
are a separate project component, not relicensed or bundled here:
https://github.com/astrobleem/oemdisplay-tandy/tree/main/tools/WHEEL/WIN16
It supplies vertical scrolling for supported focused controls; it is not a
universal adapter for every application. In particular, this package does
not add a Write-specific scrolling adapter or a WM_MOUSEWHEEL implementation.

## API for clients

GetModuleHandle("MOUSE"), then GetProcAddress by the uppercase exported name
or ordinal. Use FAR PASCAL Win16 calls. Existing ordinals 10-13 are retained.

- 10 WHEELAPIVERSION: AX=0100h.
- 11 WHEELREADDELTA: signed AX, -8..7; zero when the queue is empty.
- 12 WHEELLOSTPACKETS: cumulative lost chunks, saturating at FFFFh until reset.
- 13 WHEELREADDELTAAGE: signed delta in AX and age in BIOS ticks in DX.
  FFFFh means empty/unknown/too old, including midnight rollover. The combined
  return is DX:AX (a Win16 unsigned long); low word is the signed delta.
- 14 WHEELSTATUS: 0000h inactive, 0101h serial parser ready, 0002h DOS pointer
  without wheel, 0102h DOS wheel advertised, 8001h incompatible DOS driver,
  8002h no DOS driver in the DOS-only build.

The queue holds 31 chunks and drops newest on overflow. DOS deltas -128..127
are split into -8..7 chunks in order so older clients keep working. A chunk
is not necessarily one physical detent. Disable clears pending events and
loss counters. No USER work is performed by an external polling client in
interrupt context; the Windows movement callback remains in the driver.

## Build and checks

The checked-in binaries are experimental candidate 0.1. Driver and DOS
probe assembly use MASM 5.10 / LINK4, .8086 instructions and no DDK macros or
runtime objects. WDIAG uses Microsoft C 6.0 /G0 /Gw /AS plus Windows 3.0
headers/import libraries and its compiler runtime. Supply your own tools.

Host checks (Python 3.8+):

    python3 -m unittest discover -s tests -p test_vectors.py
    python3 scripts/check_all.py
    python3 scripts/package.py --out dist/WHEEL01.ZIP

Rebuild and run the native regression tests in a disposable DOSBox-X session:

    python3 scripts/build.py --dosbox /path/to/dosbox-x --toolchain /path/to/tools --out build

The toolchain directory must contain BIN/MASM.EXE, BIN/LINK4.EXE, BIN/CL.EXE,
INCLUDE, DDK/286/INC and LIB. These are not supplied. Do not execute the native
fixture programs on a real DOS installation: they temporarily replace INT33
and exercise COM1 loopback. Diagnostic fixtures are also emulator-only.
The clean rebuild reproduces all six checked-in runtime files byte for byte.
The host workflow does not compile the driver; passing CI is not a rebuild.

Checks performed for this candidate:
- Serial decoder: 7 host tests and 263,951 records executed by the actual
  assembled 8086 decoder, including signed coordinates, packet recovery,
  wheel values, queue overflow and reset.
- Native driver: synthetic DOS callbacks exercise detection, version-failure
  rejection, repeated enable/disable, original callback restoration, signed
  wheel extremes, cumulative motion, overflow, ages and register preservation.
- Native serial COM1 loopback exercises the actual UART receive IRQ, motion,
  wheel decoding and zeroed extra callback arguments in DOSBox-X.
- Windows 3.0 real-mode load/API/exit checks passed for Auto, DOS-only, COM1
  and COM2 on an emulated 8086 with 640 KB and no EMS/XMS/UMB. Each reported
  its expected backend, zero diagnostic failures and returned to DOS.
- Binary guards check exports, fixed/preloaded segments, no imports, and
  relocation/prologue safety. The DOS probe has synthetic failure/sign tests.

Physical serial wheel, physical PS/2 through a DOS driver, real CuteMouse /
Microsoft driver integration and PMMOUSE/PicoMEM acceptance remain unverified.
No hardware compatibility claim follows from the emulator checks.

## License

Original driver, diagnostics and test/build source here: MIT, see LICENSE.
Required external tools, operating systems and optional third-party software
retain their own licenses and are not included.
