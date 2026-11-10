@echo off
masm MOCK33.ASM,MOCK33.OBJ,MOCK33.LST,NUL;
if errorlevel 1 goto end
link4 MOCK33.OBJ,MOCK33.EXE,MOCK33.MAP,,;
:end
