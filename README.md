# Win3 Wheel Mouse

[Download the ready-to-run test ZIP](downloads/WHEEL02.ZIP) and extract it to
C:\ so it creates C:\WHEEL02. The drivers and test programs are already built.

This experimental driver provides **direct PS/2 and serial mouse support for
Windows 3.0 real mode, without a separate DOS mouse driver**. Wheel data is
available to compatible Windows XT programs and the included diagnostic.
Windows 3.1/3.11 and protected/enhanced modes are not supported by this build.

## Choose your driver

- **WPS2.DRV:** a mouse connected to a real PS/2 mouse port, including standard
  PS/2 mice and IntelliMouse-compatible wheel mice. The BIOS must report a
  PS/2 pointing device and an AT-style controller with IRQ12.
- **WCOM1.DRV / WCOM2.DRV:** a Microsoft-compatible serial mouse on COM1 / COM2,
  with or without an IntelliMouse-compatible serial wheel.
- **WHEEL.DRV:** automatic direct selection. Tries PS/2, then COM1 only if the
  BIOS reports no PS/2 interface. A busy port or failed PS/2 initialization
  stops the driver instead of silently switching hardware.
- **WDOS.DRV:** an optional adapter for an existing compatible DOS mouse driver,
  including the PicoMEM test described below. It is not needed for direct
  PS/2 or serial use.

A USB mouse needs an adapter or firmware that actually presents one of these
supported interfaces. A passive plug adapter alone cannot add that capability.

## Install

These examples assume Windows is in C:\WINDOWS. Substitute your real Windows
folder if it is different. Use a spare installation for this test package,
and keep the keyboard available if the pointer does not work.

1. Exit Windows. For direct PS/2 or serial use, disable any DOS mouse-driver
   startup line in AUTOEXEC.BAT or CONFIG.SYS, then reboot. Do not merely
   unload it: the direct PS/2 driver needs the normal cold-boot state, with
   the keyboard enabled and the mouse interface disabled. Do not share the
   selected port or IRQ with a modem or another active device.
2. Back up SYSTEM.INI and any existing WHEEL.DRV. Use unused backup names so
   you do not overwrite an earlier recovery copy. For example:

       COPY C:\WINDOWS\SYSTEM.INI C:\WINDOWS\SYSWHL.BAK
       COPY C:\WINDOWS\WHEEL.DRV C:\WINDOWS\WHLSAVE.DRV

   The second command applies only if WHEEL.DRV already exists.
3. Copy ONE driver. For a PS/2 mouse:

       COPY C:\WHEEL02\DRIVERS\WPS2.DRV C:\WINDOWS\WHEEL.DRV

   For a serial mouse on COM1:

       COPY C:\WHEEL02\DRIVERS\WCOM1.DRV C:\WINDOWS\WHEEL.DRV

   Use WCOM2.DRV instead for COM2, or WHEEL.DRV for automatic selection.
4. In C:\WINDOWS\SYSTEM.INI, find [boot] and change the existing mouse.drv
   line to:

       mouse.drv=WHEEL.DRV

   Leave the other settings alone. This is a Windows driver. Do not add a
   DEVICE= line for it to CONFIG.SYS or run it from AUTOEXEC.BAT.
5. Start Windows with WIN /R. If you use the Windows XT Tandy display package,
   keep using its normal memory-reserving launcher instead of bypassing it.
6. In Program Manager, choose File / Run and enter:

       C:\WHEEL02\WDIAG.EXE

## Test movement, buttons and wheel

Stop WXTWHL with WXTWHL /STOP, and close TP or other wheel-reading programs
before opening WDIAG. Otherwise they can take events before the diagnostic
sees them.

Move and click inside WDIAG, then turn the wheel both ways. Watch its movement,
click and wheel counters. Close with Alt+F4. It writes WDIAG.LOG in its working
directory; save or rename the log before another run.

- **Direct PS/2 / wheel negotiated:** the mouse accepted the wheel protocol.
  Wheel counters must still change to prove wheel delivery.
- **Direct PS/2 / standard mouse:** movement and two buttons are available;
  this device did not accept the wheel protocol.
- **Direct serial / wheel parser ready:** serial reception is enabled. This
  message alone does not prove that a mouse or wheel is connected.
- **STOPPED:** follow the displayed reason. For a busy PS/2 port, remove the
  DOS mouse startup line and cold reboot. After a command or cleanup failure,
  reboot before trying again. Include the status and log in your report.

WDIAG tests input; it does not make other applications scroll. Existing
Windows XT users can close WDIAG and restart WXTWHL for scrolling in supported
controls. That separate helper is not included here, and this package does
not add a scrolling adapter for Write.

## Restore the old driver

Exit Windows and restore the backups you made. With the example names above:

    COPY C:\WINDOWS\SYSWHL.BAK C:\WINDOWS\SYSTEM.INI
    COPY C:\WINDOWS\WHLSAVE.DRV C:\WINDOWS\WHEEL.DRV

Only run the second command if you made that backup. Restore any DOS mouse
startup line you disabled, then reboot.

## Optional PicoMEM / PMMOUSE test

PicoMEM's wheel-data path still needs its upstream fix. This package does not
change PicoMEM firmware, BIOS or PMMOUSE, and does not claim its wheel works.
That remains separate from the direct PS/2 and serial drivers above.

Load PMMOUSE.EXE in plain DOS before Windows. It is a command, normally run
from AUTOEXEC.BAT, not a CONFIG.SYS device. For example:

    C:\PICOMEM\PMMOUSE.EXE

PMMOUSE is not included. Do not load a second DOS mouse driver alongside it.
Choose the optional DOS adapter at installation step 3:

    COPY C:\WHEEL02\DRIVERS\WDOS.DRV C:\WINDOWS\WHEEL.DRV

Before Windows, run C:\WHEEL02\WHEELCHK /Q to check the DOS wheel capability.
Run it without /Q to watch wheel values for about 30 seconds. Missing wheel
capability does not by itself mean movement and buttons cannot work. The DOS
adapter requires the callback-exchange interface of a compatible version
6.26-or-newer mouse driver; WDIAG reports unsupported drivers rather than
trying to take over their hardware.

## What to send back

Send the computer and Windows version, mouse model, selected driver, WDIAG.LOG,
and what happened when you moved, clicked and turned the wheel. For PicoMEM,
include the firmware/PMMOUSE version and WHEELCHK output. Please also check
that ordinary typing and the old mouse setup still work after leaving Windows.

This is a hardware-test candidate, not a universal compatibility claim.
Emulator checks cover the assembled decoder, direct controller/interrupt path,
and Windows loading. Physical serial, PS/2 and PicoMEM acceptance is still
needed. COM3/4, middle/extra buttons, horizontal wheels, direct USB, and
nonstandard touchpad/absolute protocols are not supported. Direct PS/2 starts
and ends with mouse defaults; it does not preserve another driver's private
mouse settings. Use the normal BIOS timer rate while testing.

[Developer notes and source interface](DEVELOP.md) are separate from these
installation instructions. Original project code is MIT licensed; see LICENSE.
