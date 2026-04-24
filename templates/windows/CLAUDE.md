# Windows field diagnostics

You are running on a customer's Windows machine via a portable Claude Code
install. Be conservative: inspect first, change nothing without the user's
explicit instruction.

## Standard triage commands (PowerShell)

### System overview

- `Get-ComputerInfo | Select-Object CsName, OsName, OsArchitecture, OsVersion, WindowsBuildLabEx, CsSystemFamily, CsModel`
- `Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 20`
- `systeminfo /fo csv | ConvertFrom-Csv`

### Drivers / hardware

- `pnputil /enum-drivers`
- `driverquery /fo csv /v`
- `Get-PnpDevice | Where-Object Status -ne OK`

### Event logs

- `Get-WinEvent -LogName System -MaxEvents 50 | Where-Object LevelDisplayName -in Error,Warning`
- `Get-WinEvent -LogName Application -MaxEvents 50 | Where-Object LevelDisplayName -in Error,Warning`
- `wevtutil qe System /c:20 /rd:true /f:text /q:"*[System[(Level=1 or Level=2)]]"`

### Network

- `ipconfig /all`
- `Get-NetAdapter | Where-Object Status -eq Up`
- `Get-NetIPAddress -AddressFamily IPv4`
- `netsh wlan show wlanreport` (writes an HTML report under
  `C:\ProgramData\Microsoft\Windows\WlanReport\`; preview, don't leave behind)

### Storage

- `Get-PhysicalDisk | Format-Table FriendlyName, MediaType, Size, HealthStatus, OperationalStatus`
- `Get-Volume | Format-Table DriveLetter, FileSystemLabel, Size, SizeRemaining, HealthStatus`

### Integrity / repair (read-only variants first)

- `sfc /verifyonly` (inspect before running `sfc /scannow`)
- `DISM /Online /Cleanup-Image /ScanHealth` (inspect before `/RestoreHealth`)

### Defender

- `Get-MpComputerStatus | Select-Object AMRunningMode, AntivirusEnabled, RealTimeProtectionEnabled, NISEnabled, AntivirusSignatureAge`
- `Get-MpThreatDetection | Select-Object -First 20 DetectionID, ThreatName, Resources, InitialDetectionTime`

## Rules of engagement on customer boxes

1. **Read before write.** No repair commands (`sfc /scannow`, `DISM
   /RestoreHealth`, driver reinstalls) without explicit user go-ahead.
2. **Never modify registry, services, or scheduled tasks** without the user
   asking for that specific change.
3. **Leave nothing behind.** If you create a report file (e.g.
   `netsh wlan show wlanreport`), copy it into this folder's `work/` dir
   and delete the original.
4. **Document findings in `work/<ticket>.md`** as you go. The `work/` dir
   travels with this folder when you eject.
