---
name: event-log-summary
description: Summarize recent Windows Event Log errors and warnings from System + Application logs. Groups by source + event ID, highlights top repeat offenders.
---

# Event log summary

Invoke when a user says "it's been acting up" without specifics, or as a
baseline for any other investigation.

## Steps

1. **Pull recent errors/warnings**
   ```powershell
   $events = Get-WinEvent -FilterHashtable @{
     LogName=@('System','Application')
     Level=@(1,2,3)            # 1=Critical, 2=Error, 3=Warning
     StartTime=(Get-Date).AddDays(-7)
   } -ErrorAction SilentlyContinue
   ```

2. **Group by source + ID**
   ```powershell
   $events |
     Group-Object LogName, ProviderName, Id |
     Sort-Object Count -Descending |
     Select-Object -First 20 Count, Name, @{n='Sample';e={$_.Group[0].Message.Substring(0, [Math]::Min(150, $_.Group[0].Message.Length))}}
   ```

3. **Highlight critical (Level 1) events separately** — these warrant immediate attention:
   ```powershell
   $events |
     Where-Object Level -eq 1 |
     Select-Object TimeCreated, LogName, ProviderName, Id, Message
   ```

4. **Check for known hardware indicators** (disk errors, WHEA, bugchecks):
   ```powershell
   $events |
     Where-Object { $_.ProviderName -in 'disk','Ntfs','Microsoft-Windows-WHEA-Logger','BugCheck' } |
     Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message
   ```

## Output format

`work/<ticket>-eventlog.md` with:

- Top-20 repeat-offender table (Count / Source / Event ID / sample message)
- Critical events table (if any)
- Hardware-indicator events (if any)
- One-paragraph plain-English summary
