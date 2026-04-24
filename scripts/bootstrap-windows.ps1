# bootstrap-windows.ps1
#
# One-shot bootstrap: downloads the latest claude-dropin Windows release ZIP
# from GitHub and extracts it to %USERPROFILE%\Downloads\ (by default).
#
# Prerequisites on the host: Windows 10+ with PowerShell 5.1+ (default).
# Requires internet access. Requires the claude-dropin repo to be public, OR
# a logged-in `gh` CLI (not assumed on customer boxes).
#
# Usage
# -----
#
# One-liner from any cmd or PowerShell terminal:
#
#     powershell -Command "irm https://raw.githubusercontent.com/mmj333/claude-dropin/main/scripts/bootstrap-windows.ps1 | iex"
#
# Launch Claude Code immediately after extraction:
#
#     powershell -Command "& { $s = (irm https://raw.githubusercontent.com/mmj333/claude-dropin/main/scripts/bootstrap-windows.ps1); iex ($s + '`n& $Launch = $true; Invoke-Bootstrap') }"
#
# Or download this file locally and run:
#
#     powershell -ExecutionPolicy Bypass -File bootstrap-windows.ps1 -Launch
#
# Parameters
# ----------
#
#   -DestDir <path>   Where to extract (default: %USERPROFILE%\Downloads)
#   -Version <tag>    Release tag to pull (default: latest)
#   -Launch           After extract, open run.cmd in a new window
#
param(
  [string]$DestDir = (Join-Path $env:USERPROFILE 'Downloads'),
  [string]$Version = 'latest',
  [switch]$Launch
)

$ErrorActionPreference = 'Stop'

$repo = 'mmj333/claude-dropin'
$asset = 'claude-dropin-v0.1-win32-x64.zip'

if ($Version -eq 'latest') {
  $url = "https://github.com/$repo/releases/latest/download/$asset"
} else {
  $url = "https://github.com/$repo/releases/download/$Version/$asset"
}

if (-not (Test-Path $DestDir)) {
  New-Item -ItemType Directory -Path $DestDir | Out-Null
}

$zipPath = Join-Path $DestDir $asset

Write-Host "==> Downloading $asset"
Write-Host "    from: $url"
Write-Host "    to:   $zipPath"
try {
  Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
} catch {
  Write-Host ""
  Write-Host "ERROR: download failed. Check:" -ForegroundColor Red
  Write-Host "  - network connectivity"
  Write-Host "  - whether https://github.com/$repo is public"
  Write-Host "  - whether a release named '$Version' exists with asset '$asset'"
  throw
}

Write-Host "==> Extracting to $DestDir"
# Expand-Archive won't overwrite by default; -Force handles repeat runs.
Expand-Archive -Path $zipPath -DestinationPath $DestDir -Force
Remove-Item $zipPath

$folder = Get-ChildItem -Path $DestDir -Directory -Filter 'claude-dropin-v*' `
  | Sort-Object LastWriteTime -Descending `
  | Select-Object -First 1

if (-not $folder) {
  Write-Host "ERROR: extracted but no claude-dropin-v* folder in $DestDir" -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "Ready at: $($folder.FullName)" -ForegroundColor Green
Write-Host "Launch:   $($folder.FullName)\run.cmd"

if ($Launch) {
  Write-Host ""
  Write-Host "==> Launching run.cmd..."
  # Start in a new console window so the caller's terminal stays free.
  Start-Process -FilePath "$($folder.FullName)\run.cmd" -WorkingDirectory $folder.FullName
}
