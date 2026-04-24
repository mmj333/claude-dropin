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
# Invoke-WebRequest's default progress bar on PS 5.1 pegs the download at
# single-digit MB/s on any size file — the progress redraw is the bottleneck.
# HttpClient with a buffered stream download is 10-20x faster in practice.
try {
  Add-Type -AssemblyName System.Net.Http
  $client = [System.Net.Http.HttpClient]::new()
  $client.Timeout = [TimeSpan]::FromMinutes(10)
  $response = $client.GetAsync($url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
  if (-not $response.IsSuccessStatusCode) {
    throw "HTTP $([int]$response.StatusCode) $($response.ReasonPhrase)"
  }
  $total = $response.Content.Headers.ContentLength
  $in    = $response.Content.ReadAsStreamAsync().Result
  $out   = [System.IO.File]::Create($zipPath)
  try {
    $buf = New-Object byte[] 131072
    $read = 0
    $t0 = Get-Date
    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
      $out.Write($buf, 0, $n)
      $read += $n
      if ($total -gt 0 -and ((Get-Date) - $t0).TotalMilliseconds -gt 250) {
        $pct = [int](100 * $read / $total)
        Write-Host -NoNewline "`r    $pct%  ($([int]($read/1MB))/$([int]($total/1MB)) MB)"
        $t0 = Get-Date
      }
    }
    Write-Host "`r    100% ($([int]($read/1MB)) MB)               "
  } finally {
    $out.Close()
    $in.Close()
  }
} catch {
  Write-Host ""
  Write-Host "ERROR: download failed. Check:" -ForegroundColor Red
  Write-Host "  - network connectivity"
  Write-Host "  - whether https://github.com/$repo is public"
  Write-Host "  - whether a release named '$Version' exists with asset '$asset'"
  throw
}

# tar.exe (bsdtar / libarchive) ships with Windows 10 build 17063+ and
# Server 2019+. It handles ZIPs and is typically 2-3x faster than
# Expand-Archive on archives with many small files (MinGit has ~370).
# Fall back to Expand-Archive on older boxes (pre-1809, Server 2016).
$tarExe = Get-Command tar.exe -ErrorAction SilentlyContinue
$engine = if ($tarExe) { 'tar.exe' } else { 'Expand-Archive' }
Write-Host "==> Extracting to $DestDir  (engine: $engine)"
$extractStart = [Diagnostics.Stopwatch]::StartNew()
if ($tarExe) {
  & $tarExe.Path -xf $zipPath -C $DestDir
  if ($LASTEXITCODE -ne 0) {
    Write-Host "    tar.exe returned $LASTEXITCODE; falling back to Expand-Archive..."
    Expand-Archive -Path $zipPath -DestinationPath $DestDir -Force
    $engine = 'Expand-Archive (tar.exe fell back)'
  }
} else {
  Expand-Archive -Path $zipPath -DestinationPath $DestDir -Force
}
$extractStart.Stop()
Write-Host ("    done in {0:N1}s via {1}" -f $extractStart.Elapsed.TotalSeconds, $engine)
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
