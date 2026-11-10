@echo off
rem Requires MASM 5.1 and LINK4.EXE on PATH. Tools are not included.
masm WHEELCHK.ASM,WHEELCHK.OBJ,WHEELCHK.LST,NUL;
if errorlevel 1 goto failed
link4 WHEELCHK.OBJ,WHEELCHK.EXE,WHEELCHK.MAP,,;
if errorlevel 1 goto failed
echo WHEELCHK build completed.
goto end
:failed
echo WHEELCHK build failed. Check assembler/linker output.
:end
