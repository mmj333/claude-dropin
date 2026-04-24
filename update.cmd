@echo off
setlocal enabledelayedexpansion
rem update.cmd -- pull latest scripts/templates from github.com/mmj333/claude-dropin.
rem
rem PRESERVES: config\, work\, vendor\, dist\, .build-cache\
rem UPDATES:   run.cmd, setup.cmd, eject.cmd, update.cmd, lib\, scripts\,
rem            templates\, README.md, CREDITS.md, LICENSE, .gitignore
rem
rem Does NOT refresh bundled binaries in vendor\. For that, use the
rem release ZIP (bootstrap-windows.ps1) or rebuild with scripts\build-windows.sh.
rem
rem First-time install:
rem   curl -fsSL https://raw.githubusercontent.com/mmj333/claude-dropin/main/update.cmd -o update.cmd
rem   update.cmd

rem -- Respawn from %TEMP% so we can safely overwrite update.cmd itself.
rem cmd.exe streams batch files from disk line-by-line; overwriting the
rem running .cmd can corrupt the interpreter. The temp copy is cleaned
rem up on exit.
if not defined CLAUDE_DROPIN_UPDATE_RESPAWNED (
  set "TMP_SELF=%TEMP%\claude-dropin-update-%RANDOM%%RANDOM%.cmd"
  copy /y "%~f0" "!TMP_SELF!" >nul
  set "CLAUDE_DROPIN_UPDATE_RESPAWNED=1"
  set "CLAUDE_DROPIN_ORIG_DIR=%~dp0"
  call "!TMP_SELF!" %*
  set "UPDATE_RC=!ERRORLEVEL!"
  del /f /q "!TMP_SELF!" 2>nul
  endlocal
  exit /b %UPDATE_RC%
)

rem -- Now running from %TEMP%; real script dir is in CLAUDE_DROPIN_ORIG_DIR.
set "SCRIPT_DIR=%CLAUDE_DROPIN_ORIG_DIR%"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "REPO=mmj333/claude-dropin"
set "BRANCH=main"
if not "%~1"=="" set "BRANCH=%~1"
set "TARBALL_URL=https://github.com/%REPO%/archive/refs/heads/%BRANCH%.tar.gz"

set "TMPROOT=%TEMP%\claude-dropin-update-%RANDOM%%RANDOM%"
mkdir "%TMPROOT%"
set "TARBALL=%TMPROOT%\src.tar.gz"
set "EXTRACT=%TMPROOT%\extract"
mkdir "%EXTRACT%"

echo ==^> Fetching %REPO%@%BRANCH%...
curl -fsSL "%TARBALL_URL%" -o "%TARBALL%"
if errorlevel 1 (
  echo ERROR: download failed. Check network + whether the branch exists.
  rmdir /s /q "%TMPROOT%" 2>nul
  exit /b 1
)

rem Capture the commit SHA from the inner dir name before --strip-components=1.
rem The tarball's top-level entry is "claude-dropin-<full-sha>/".
set "INNER="
for /f "usebackq tokens=*" %%i in (`tar -tzf "%TARBALL%" ^| findstr /v /c:"/"`) do if not defined INNER set "INNER=%%i"
set "GIT_SHA=%INNER:claude-dropin-=%"
set "GIT_SHA=%GIT_SHA:/=%"

tar -xzf "%TARBALL%" -C "%EXTRACT%" --strip-components=1
if errorlevel 1 (
  echo ERROR: tar extract failed.
  rmdir /s /q "%TMPROOT%" 2>nul
  exit /b 1
)

echo ==^> Overlaying updates onto %SCRIPT_DIR%...
rem robocopy mirrors source -^> dest with XD excludes. /XD = exclude dirs;
rem we pass each protected dir relative to %SCRIPT_DIR%.
rem /NP no progress, /NS /NC /NDL /NFL cut per-file logging.
rem Exit codes 0-7 mean success; 8+ mean failure. Normalize to 0/1.
robocopy "%EXTRACT%" "%SCRIPT_DIR%" /E /NJH /NJS /NP /NFL /NDL ^
  /XD "%SCRIPT_DIR%\config" "%SCRIPT_DIR%\work" "%SCRIPT_DIR%\vendor" ^
       "%SCRIPT_DIR%\dist" "%SCRIPT_DIR%\.build-cache" "%SCRIPT_DIR%\.git" ^
  >nul
set "RC=%ERRORLEVEL%"
rem robocopy exit codes: 0-7 = success variants, 8+ = actual failure.
if %RC% GEQ 8 (
  echo ERROR: robocopy failed ^(rc=%RC%^).
  rmdir /s /q "%TMPROOT%" 2>nul
  exit /b 1
)

rmdir /s /q "%TMPROOT%" 2>nul

rem Write a VERSION marker so "am I on latest?" has a clear answer.
if defined GIT_SHA (
  ^> "%SCRIPT_DIR%\VERSION" echo %BRANCH% @ %GIT_SHA%
)

echo.
echo ==^> Update complete.
if defined GIT_SHA echo     Now at: %BRANCH% @ %GIT_SHA:~0,7%
echo.
echo Bundled binaries in vendor\ were not touched.
echo If you need fresher claude.exe / age / MinGit, re-download the
echo release ZIP via bootstrap-windows.ps1, or rebuild from source.
exit /b 0
