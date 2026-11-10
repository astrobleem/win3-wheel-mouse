@echo off
mock33.com N
..\wheelchk /Q > NULL.LOG
if errorlevel 2 goto fail
if not errorlevel 1 goto fail
mock33.com I
..\wheelchk /Q > IRET.LOG
if errorlevel 2 goto fail
if not errorlevel 1 goto fail
mock33.com O
..\wheelchk /Q > OLD.LOG
if errorlevel 3 goto fail
if not errorlevel 2 goto fail
mock33.com F
..\wheelchk /Q > VERFAIL.LOG
if errorlevel 3 goto fail
if not errorlevel 2 goto fail
mock33.com S
..\wheelchk /Q > SIG.LOG
if errorlevel 4 goto fail
if not errorlevel 3 goto fail
mock33.com C
..\wheelchk /Q > FLAG.LOG
if errorlevel 4 goto fail
if not errorlevel 3 goto fail
mock33.com W
..\wheelchk /Q > QUIET.LOG
if errorlevel 1 goto fail
..\wheelchk > WHEEL.LOG
if errorlevel 1 goto fail
echo PASS > RESULT.LOG
goto end
:fail
echo FAIL > RESULT.LOG
:end
