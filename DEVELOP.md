# Developer notes

Installation and hardware-test instructions are in [README.md](README.md).

## Candidate 0.2 transports

WHEEL.DRV tries direct PS/2, then COM1 only when the BIOS reports PS/2 absent.
WPS2.DRV selects direct PS/2. WCOM1.DRV and WCOM2.DRV select direct serial.
All direct builds refuse a resident INT 33h handler rather than taking hardware
from it. WDOS.DRV is the separate, optional DOS adapter; it never owns a UART
or PS/2 controller. Only left/right buttons are forwarded to Windows.

The direct PS/2 path uses the AT 8042 auxiliary port and IRQ12, not INT 33h or
a BIOS mouse callback. A successful INT 15h/C0 second-PIC feature check and
INT 11h pointing-device flag gate hardware access. It requires the normal
cold-boot keyboard-enabled/AUX-disabled baseline. An active AUX interface or
pending output causes a refusal. Keyboard inhibition precedes the controller
configuration read so a new scan code cannot be mistaken for that reply.

The mouse is stopped, reset, and negotiated using sample rates 200/100/80.
ID 3 uses four-byte IntelliMouse packets; ID 0 uses standard three-byte input.
Initialization and release reset the mouse to defaults; private settings of
an earlier driver are not preserved. Release restores the saved IRQ12 vector,
controller configuration and owned PIC mask bits. Failed hardware cleanup is
reported separately. Pending AUX input is drained to a bounded quiet interval;
non-AUX output is never consumed by the transport. Command waits are bounded.
BAT uses a latched PIT0 timeout assuming the normal BIOS timer mode/divisor,
with an independent instruction-count limit if the timer stops. Programs that
reprogram PIT0 are outside this candidate's tested configuration.

Serial input is 1200 baud, 7 data bits, no parity, one stop bit. The decoder
accepts Microsoft-compatible three-byte motion/buttons and an IntelliMouse
fourth wheel byte. COM1 owns IRQ4; COM2 owns IRQ3. Neither driver probes COM3/4.

The optional DOS adapter needs Microsoft-compatible version 6.26+ and
INT 33h/AX=0014h callback exchange. Wheel input needs AX=0011h to return
AX=574Dh, CX bit 0, and callback mask bit 7 with signed BH deltas. SI/DI are
cumulative mickeys. No mouse reset or range/ratio change is performed. Disable
restores the previous callback pair. Other programs must not consume the same
counters or replace the callback while Windows owns this backend.

## API for clients

GetModuleHandle("MOUSE"), then GetProcAddress by uppercase export or ordinal.
Calls are FAR PASCAL Win16. Existing ordinals and version are retained.

- 10 WHEELAPIVERSION: AX=0100h.
- 11 WHEELREADDELTA: signed AX, -8..7; zero when empty.
- 12 WHEELLOSTPACKETS: lost chunks, saturating at FFFFh until reset.
- 13 WHEELREADDELTAAGE: signed delta AX, age in BIOS ticks DX. FFFFh means
  empty/unknown/too old, including midnight rollover. Return type is DX:AX,
  a Win16 unsigned long, with the low word interpreted as a signed integer.
- 14 WHEELSTATUS:
  - 0000h inactive.
  - 0101h direct serial parser ready.
  - 0002h DOS pointer without advertised wheel; 0102h DOS wheel advertised.
  - 0003h direct standard PS/2; 0103h direct PS/2 wheel negotiated.
  - 8001h incompatible DOS driver; 8002h no DOS driver in WDOS.
  - 8003h PS/2 not reported; 8004h PS/2 busy/pending input.
  - 8005h PS/2 command failed; 8006h cleanup failed, reboot needed.
  - 8007h resident DOS mouse prevents direct hardware ownership.

The queue holds 31 chunks and drops newest on overflow. DOS and PS/2 signed
wheel bytes are split into -8..7 chunks in order. A chunk need not be one
physical detent. Disable clears queued events and loss counters. A polling
client must not call USER from interrupt context; Windows pointer callbacks
are delivered by the driver itself. MouseGetIntVect reports 74h for PS/2.

WDIAG /AUTO is a load/API/exit check: it exits Windows after five timer ticks.
It is not proof of physical input. WHEELCHK checks only the optional DOS path;
/Q does not consume wheel counters. Its exit codes are 0 wheel advertised,
1 absent vector, 2 unavailable/old version, 3 no wheel capability, 4 bad option.

## Build and regression checks

Drivers and DOS probe use MASM 5.10 / LINK4, .8086 instructions, and no DDK
macros or runtime objects. WDIAG uses Microsoft C 6.0 /G0 /Gw /AS with Windows
3.0 headers/import libraries and its compiler runtime. Supply your own tools.

Host checks (Python 3.8+):

    python3 -m unittest discover -s tests -p test_vectors.py
    python3 scripts/check_all.py
    python3 scripts/package.py --out dist/WHEEL02.ZIP

Build and native regression tests in disposable DOSBox-X sessions:

    python3 scripts/build.py --dosbox /path/to/dosbox-x --toolchain /path/to/tools --out build

The toolchain directory needs BIN/MASM.EXE, BIN/LINK4.EXE, BIN/CL.EXE, INCLUDE,
DDK/286/INC and LIB. They are not supplied. Test fixtures temporarily replace
interrupt vectors, use UART loopback or inject controller bytes. Never run
those fixtures on a real DOS installation. They are source-only in the ZIP;
WDIAG and WHEELCHK are the user-facing diagnostics.

The build runs the actual assembled serial decoder over 263,951 vectors and
the assembled PS/2 decoder over 8,841 assertions, including all signed wheel
bytes, 2,304 wheel chunks, motion, buttons, overflow, queue order and timestamps.
Native tests cover the DOS adapter and serial receive IRQ. PS/2 hardware tests
exercise emulated controller commands, wheel negotiation, IRQ12 callbacks and
repeated lifecycle restoration with standard and wheel mouse configurations.
Refusal tests cover existing owners and pending keyboard input. Missing-device
tests cover BIOS rejection and a forced missing-ACK path, including keyboard
re-enablement after reported cleanup failure. These are
emulator results, not physical hardware certification.

The checked-in images are also inspected for the expected exports, fixed and
preloaded segments, no imports, and safe loader relocations/prologues. The
GitHub workflow runs host tests and packaging, not a MASM rebuild. Windows
3.0 real-mode load/API/exit checks passed for direct PS/2, automatic PS/2,
COM1, COM2, the optional DOS adapter, and automatic COM1 on an XT configuration.
They ran on an emulated 8086 with 640 KB and no EMS/XMS/UMB, separately from
the native DOS fixtures. No physical input was claimed by those load checks.

Physical serial and PS/2 acceptance, real DOS-driver integration, and the
PicoMEM/PMMOUSE wheel path remain unverified. PicoMEM firmware changes belong
to its upstream work, not this driver package.
