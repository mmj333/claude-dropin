---
name: triage-slow-boot
description: Diagnose slow Windows boot / login times. Collect boot-time telemetry, identify high-impact startup items, flag driver and service stalls.
---

# Triage slow boot

Invoke when a user reports "Windows takes forever to start" or "login hangs".

## Steps

1. **Boot performance from Event Log**
   ```powershell
   Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' `
     -MaxEvents 20 |
     Where-Object Id -in 100, 101, 102, 103 |
     Select-Object TimeCreated, Id, Message
   ```
   - Event 100: boot time summary (BootDuration, MainPathBootTime)
   - Event 101: slow application (takes >~5s)
   - Event 102: slow driver (>200ms)
   - Event 103: slow service (>~20s)

2. **Startup items**
   ```powershell
   Get-CimInstance Win32_StartupCommand |
     Select-Object Name, Command, Location, User |
     Sort-Object Name
   ```

3. **Auto-start services in pending/stopped states**
   ```powershell
   Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' }
   ```

4. **Disk health** (slow boot is often a failing disk)
   ```powershell
   Get-PhysicalDisk | Where-Object HealthStatus -ne Healthy
   Get-StorageReliabilityCounter -PhysicalDisk (Get-PhysicalDisk) -ErrorAction SilentlyContinue
   ```

## Output format

Write findings to `work/<ticket>-slow-boot.md` with:

- Boot time summary (total, main-path, post-boot)
- Top 3 offenders (app / driver / service) with their measured delay
- Disk health verdict
- Recommendation (user-facing, one paragraph)
