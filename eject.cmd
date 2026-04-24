@echo off
setlocal enabledelayedexpansion
rem eject.cmd -- idempotent force-encrypt + shred of any leftover scratch dir.
rem Use when a crash (or "Terminate batch job Y/N -> Y") left a decrypted
rem scratch dir behind. No-op if no scratch is found.

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "VENDOR_DIR=%SCRIPT_DIR%\vendor\win32-x64"
set "AGE_BIN=%VENDOR_DIR%\age.exe"
set "CONFIG_DIR=%SCRIPT_DIR%\config"
set "SCRATCH=%CONFIG_DIR%\scratch"
set "TAR_TMP=%CONFIG_DIR%\.blob.tar.tmp"

rem Clean any stale .new from a prior crashed encrypt.
if exist "%CONFIG_DIR%\claude.age.new" del /f /q "%CONFIG_DIR%\claude.age.new"

if not exist "%SCRATCH%" (
  echo Nothing to eject -- no scratch dir found.
  endlocal
  exit /b 0
)
if not exist "%CONFIG_DIR%\recipient.pub" (
  echo ERROR: %CONFIG_DIR%\recipient.pub missing.
  echo Cannot re-encrypt without it. Preserve %SCRATCH% and investigate.
  endlocal
  exit /b 1
)

echo ==^> Re-encrypting %SCRATCH%...
set /p RECIPIENT=<"%CONFIG_DIR%\recipient.pub"
pushd "%SCRATCH%"
tar -c -f "%TAR_TMP%" .
set "RC=!ERRORLEVEL!"
popd
if not "!RC!"=="0" (
  echo ERROR: tar create failed ^(rc=!RC!^). Scratch preserved at %SCRATCH%.
  if exist "%TAR_TMP%" del /f /q "%TAR_TMP%"
  endlocal
  exit /b 1
)
"%AGE_BIN%" -e -r "!RECIPIENT!" -o "%CONFIG_DIR%\claude.age.new" "%TAR_TMP%"
set "RC=!ERRORLEVEL!"
del /f /q "%TAR_TMP%" 2>nul
if not "!RC!"=="0" (
  echo ERROR: encryption failed ^(rc=!RC!^). Scratch preserved at %SCRATCH%.
  if exist "%CONFIG_DIR%\claude.age.new" del /f /q "%CONFIG_DIR%\claude.age.new"
  endlocal
  exit /b 1
)

move /y "%CONFIG_DIR%\claude.age.new" "%CONFIG_DIR%\claude.age" >nul
rmdir /s /q "%SCRATCH%"
echo ==^> Ejected.
endlocal
exit /b 0
