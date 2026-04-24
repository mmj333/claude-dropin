@echo off
setlocal enabledelayedexpansion
rem run.cmd -- launch Claude Code with encrypted folder-local config.
rem Mirrors run.sh. Decrypts config\claude.age to a scratch dir under config\,
rem sets CLAUDE_CONFIG_DIR + ANTHROPIC_API_KEY, cd's into work\, runs claude,
rem re-encrypts + shreds scratch on exit.

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "VENDOR_DIR=%SCRIPT_DIR%\vendor\win32-x64"
set "CLAUDE_BIN=%VENDOR_DIR%\claude.exe"
set "AGE_BIN=%VENDOR_DIR%\age.exe"
set "AGE_KEYGEN=%VENDOR_DIR%\age-keygen.exe"
set "CONFIG_DIR=%SCRIPT_DIR%\config"
set "WORK_DIR=%SCRIPT_DIR%\work"
set "SCRATCH=%CONFIG_DIR%\scratch"
set "GIT_DIR=%SCRIPT_DIR%\vendor\git-for-windows"
set "TAR_TMP=%CONFIG_DIR%\.blob.tar.tmp"

rem -- Preflight ---------------------------------------------------------
if not exist "%CLAUDE_BIN%" (
  echo ERROR: %CLAUDE_BIN% not found.
  echo Run scripts\build-windows.sh on a Linux build host, then package.sh.
  pause
  exit /b 1
)
if not exist "%AGE_BIN%" (
  echo ERROR: %AGE_BIN% not found.
  pause
  exit /b 1
)
if not exist "%CONFIG_DIR%\claude.age" (
  echo No config blob found. Running setup...
  call "%SCRIPT_DIR%\setup.cmd"
  if errorlevel 1 exit /b %ERRORLEVEL%
)

rem -- Clean stale .new from a prior crashed encrypt --------------------
if exist "%CONFIG_DIR%\claude.age.new" del /f /q "%CONFIG_DIR%\claude.age.new"

rem -- Clean any prior scratch (crash recovery) --------------------------
rem Shred, DO NOT re-encrypt: a crashed scratch holds plaintext whose
rem recipient.pub may have been tampered with while the process was down.
rem Re-encrypting would leak to an attacker's key. Crash = session lost
rem (per README "Known issues"). For explicit recovery, user runs
rem `eject.cmd` manually after verifying recipient.pub.
if exist "%SCRATCH%" (
  echo Warning: found crashed scratch at %SCRATCH% — shredding without re-encrypt.
  echo          Session state from the prior run is lost.
  rmdir /s /q "%SCRATCH%"
)
mkdir "%SCRATCH%"

rem -- Decrypt identity --------------------------------------------------
set "IDENTITY_PLAIN=%SCRATCH%\.identity.plain"
if defined CLAUDE_DROPIN_PASSPHRASE (
  rem Normal %%...%% expansion, not !...! — preserves `!` in passphrases.
  rem Note: passphrases containing `%%` or `"` are not supported via env var.
  set "PATH=%VENDOR_DIR%;%PATH%"
  set "AGE_PASSPHRASE=%CLAUDE_DROPIN_PASSPHRASE%"
  "%AGE_BIN%" -d -j batchpass -o "%IDENTITY_PLAIN%" "%CONFIG_DIR%\identity.age"
  set "RC=!ERRORLEVEL!"
  set "AGE_PASSPHRASE="
) else (
  echo ==^> Unlocking config...
  "%AGE_BIN%" -d -o "%IDENTITY_PLAIN%" "%CONFIG_DIR%\identity.age"
  set "RC=!ERRORLEVEL!"
)
if not "!RC!"=="0" (
  echo ERROR: identity decrypt failed ^(wrong passphrase?^).
  call :_abort
  exit /b 1
)

rem -- Key-swap attack guard: derive pubkey and compare to recipient.pub
rem Use a tempfile + set /p to avoid the nested-quote for-backtick fragility.
"%AGE_KEYGEN%" -y "%IDENTITY_PLAIN%" > "%SCRATCH%\.derived.pub" 2>nul
set /p DERIVED_PUB=<"%SCRATCH%\.derived.pub"
del /f /q "%SCRATCH%\.derived.pub" 2>nul
set /p EXPECTED_PUB=<"%CONFIG_DIR%\recipient.pub"
if not "!DERIVED_PUB!"=="!EXPECTED_PUB!" (
  echo ERROR: config\recipient.pub does not match the identity's public key.
  echo        Possible tampering ^(key-swap attack^). Refusing to continue.
  echo        Inspect the folder; if legitimate, re-run setup.cmd --force.
  call :_abort
  exit /b 1
)

rem -- Decrypt blob (two-step to avoid pipe-error silent swallow) --------
"%AGE_BIN%" -d -i "%IDENTITY_PLAIN%" -o "%TAR_TMP%" "%CONFIG_DIR%\claude.age"
if errorlevel 1 (
  echo ERROR: blob decrypt failed.
  call :_abort
  exit /b 1
)
del /f /q "%IDENTITY_PLAIN%" 2>nul

pushd "%SCRATCH%"
tar -x -f "%TAR_TMP%"
set "RC=!ERRORLEVEL!"
popd
del /f /q "%TAR_TMP%" 2>nul
if not "!RC!"=="0" (
  echo ERROR: tar extract failed ^(rc=!RC!^).
  call :_abort
  exit /b 1
)

rem -- Env setup ---------------------------------------------------------
set "CLAUDE_CONFIG_DIR=%SCRATCH%\claude"
set "CLAUDE_CODE_USE_POWERSHELL_TOOL=1"

if exist "%SCRATCH%\api-key" (
  rem `set /p` is single-line + strips CR, unlike `for /f` which chokes on trailing blanks.
  set /p ANTHROPIC_API_KEY=<"%SCRATCH%\api-key"
)

rem Belt-and-suspenders: redirect any subprocess writes inside SCRATCH.
set "TMP=%SCRATCH%\tmp"
set "TEMP=%SCRATCH%\tmp"
set "APPDATA=%SCRATCH%\appdata"
set "LOCALAPPDATA=%SCRATCH%\localappdata"
set "XDG_CONFIG_HOME=%SCRATCH%\xdg-config"
if not exist "%TMP%"             mkdir "%TMP%"
if not exist "%APPDATA%"         mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%"    mkdir "%LOCALAPPDATA%"
if not exist "%XDG_CONFIG_HOME%" mkdir "%XDG_CONFIG_HOME%"

rem Prepend bundled Git (MinGit) to PATH if present.
if exist "%GIT_DIR%\cmd\git.exe" set "PATH=%GIT_DIR%\cmd;%GIT_DIR%\mingw64\bin;%PATH%"

rem Don't leak our override env vars into claude or anything it spawns.
set "CLAUDE_DROPIN_PASSPHRASE="
set "CLAUDE_DROPIN_API_KEY="

rem -- Pick per-host work subdir (session history scoped to the machine).
rem Same folder plugged into different machines -> different cwds ->
rem claude indexes their session histories separately. Set
rem CLAUDE_DROPIN_SHARED_WORK=1 to opt back into a single shared work\.
if not defined CLAUDE_DROPIN_SHARED_WORK (
  rem COMPUTERNAME is always set on Windows; sanitize anyway.
  set "HOST_SLUG=%COMPUTERNAME%"
  rem Replace anything not alnum/dot/dash/underscore with underscore.
  rem cmd can't do regex; COMPUTERNAME is alnum+dash only per Windows rules,
  rem so in practice no sanitization is needed. Guard for odd custom names.
  set "WORK_DIR=%WORK_DIR%\!HOST_SLUG!"
)

rem -- Launch ------------------------------------------------------------
if not exist "%WORK_DIR%" mkdir "%WORK_DIR%"
pushd "%WORK_DIR%"
"%CLAUDE_BIN%" %*
set "CLAUDE_EXIT=!ERRORLEVEL!"
popd

rem -- Re-encrypt on exit (two-step, atomic-rename) ----------------------
rem By this point decryption succeeded and we ran claude. Safe to re-encrypt
rem the scratch. (Failure paths above hit :_abort and never reach here.)
echo ==^> Re-encrypting session state...
set /p RECIPIENT=<"%CONFIG_DIR%\recipient.pub"
pushd "%SCRATCH%"
tar -c -f "%TAR_TMP%" .
set "RC=!ERRORLEVEL!"
popd
if not "!RC!"=="0" (
  echo ERROR: tar create failed ^(rc=!RC!^). Scratch left at: %SCRATCH%
  del /f /q "%TAR_TMP%" 2>nul
  endlocal & exit /b %CLAUDE_EXIT%
)
"%AGE_BIN%" -e -r "!RECIPIENT!" -o "%CONFIG_DIR%\claude.age.new" "%TAR_TMP%"
set "RC=!ERRORLEVEL!"
del /f /q "%TAR_TMP%" 2>nul
if not "!RC!"=="0" (
  echo ERROR: encrypt failed. Scratch left at: %SCRATCH%
  echo   Run eject.cmd to retry.
  if exist "%CONFIG_DIR%\claude.age.new" del /f /q "%CONFIG_DIR%\claude.age.new"
  endlocal & exit /b %CLAUDE_EXIT%
)
move /y "%CONFIG_DIR%\claude.age.new" "%CONFIG_DIR%\claude.age" >nul
if errorlevel 1 (
  echo ERROR: atomic rename claude.age.new -^> claude.age failed.
  echo   Scratch left at: %SCRATCH%
  echo   Inspect config\ and run eject.cmd to retry.
  endlocal & exit /b %CLAUDE_EXIT%
)
rmdir /s /q "%SCRATCH%"
echo ==^> Ejected cleanly.
endlocal & exit /b %CLAUDE_EXIT%

:_abort
set "AGE_PASSPHRASE="
if exist "%IDENTITY_PLAIN%"      del /f /q "%IDENTITY_PLAIN%"
if exist "%TAR_TMP%"              del /f /q "%TAR_TMP%"
if exist "%SCRATCH%"              rmdir /s /q "%SCRATCH%"
goto :eof
