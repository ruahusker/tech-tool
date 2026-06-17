# TechKit — Technician Script Library

A cross-platform diagnostic and repair script library for IT technicians — **67 scripts
(~42 tools)** across Windows and macOS. Works standalone (run scripts by hand) or as the tool
library for the **Tech Tool UI** (and the Qwen Coder Tech Agent) on this drive.

## Layout

```
TechKit/
  catalog.json     machine-readable index (id, summary, use_when, args, admin/destructive flags)
  windows/         PowerShell 5.1+ scripts (stock Windows 10/11)
  macos/           bash 3.2+ scripts (stock macOS)
  collections/     evidence bundles written here by export/triage/cleanup scripts
```

## Running scripts manually

**Windows** (from an elevated or normal PowerShell — each script reports what it needs):

```powershell
powershell -ExecutionPolicy Bypass -File "D:\TechKit\windows\Get-SystemReport.ps1"
```

**macOS** (exFAT strips execute bits, so invoke via bash):

```bash
bash "/Volumes/Tech Tool/TechKit/macos/system_report.sh"
```

## Conventions — read this once

1. **Read-only by default.** Every script diagnoses without changing anything unless you
   pass an explicit flag (`-Force` / `--force`, `-Repair`, `-ClearQueue`).
2. **Destructive scripts dry-run first.** `Remove-InactiveUsers.ps1`, `remove_inactive_users.sh`,
   `Clear-TempFiles.ps1`, `clear_caches.sh` all print exactly what they *would* do; run again
   with the force flag to apply. Destructive actions are logged to `collections/`.
3. **Admin/sudo degrades gracefully.** Scripts tell you which sections need elevation instead
   of failing.
4. **Start with triage.** On an unknown problem, run `Invoke-TriageSnapshot.ps1` /
   `triage_snapshot.sh` first — it captures everything read-only into `collections/` in a
   few minutes, so you have evidence even if the machine gets worse.

## Quick picker

| Complaint | Windows | macOS |
|---|---|---|
| Unknown / "it's broken" | Invoke-TriageSnapshot.ps1 | triage_snapshot.sh |
| Slow right now | Get-TopProcesses.ps1 | top_processes.sh |
| Slow startup | Get-StartupItems.ps1 | startup_items.sh |
| No internet | Get-NetworkDiagnostics.ps1 | network_diagnostics.sh |
| Can't reach one server | Test-Connectivity.ps1 | test_connectivity.sh |
| Crashes / random reboots | Get-EventLogSummary.ps1 | log_summary.sh |
| Disk full | Find-LargeFiles.ps1 → Clear-TempFiles.ps1 | find_large_files.sh → clear_caches.sh |
| Disk failing? | Get-DiskHealth.ps1 | disk_health.sh |
| Update problems | Get-WindowsUpdateStatus.ps1 → Repair-SystemFiles.ps1 | update_status.sh |
| Corrupt system files | Repair-SystemFiles.ps1 | (Recovery-mode First Aid) |
| Security check | Get-SecurityStatus.ps1 | security_status.sh |
| Account cleanup | Get-UserAccountReport.ps1 → Remove-InactiveUsers.ps1 | user_account_report.sh → remove_inactive_users.sh |
| Battery complaints | Get-BatteryReport.ps1 | battery_health.sh |
| Printing / stuck print job | Get-PrinterDiagnostics.ps1 → Repair-PrintSpooler.ps1 | reset_printing.sh |
| Blue screen / kernel panic | Get-CrashReport.ps1 | crash_report.sh |
| Encryption / recovery key | Get-EncryptionStatus.ps1 | encryption_status.sh |
| Can't log in to domain / GPO not applying | Get-DomainHealth.ps1 | domain_health.sh |
| Wi-Fi problems | Get-WifiDiagnostics.ps1 | wifi_diagnostics.sh |
| Hasn't really rebooted / pending reboot | Get-PendingReboot.ps1 | pending_reboot.sh |
| Suspected malware | Invoke-DefenderScan.ps1 | defender_scan.sh |
| Unwanted startup / persistence | Get-PersistenceAudit.ps1 | persistence_audit.sh |
| Back up data before reimage | Backup-UserData.ps1 | backup_user_data.sh |
| Take logs with you | Export-EventLogs.ps1 | collect_logs.sh |

## For the AI agent (phase 2)

`catalog.json` is the contract: the agent matches the user's complaint against `use_when`,
checks `admin`/`destructive` flags, fills `args`, runs the script, and **interprets the output**
(every script emits `[!]` markers on findings that need attention). For destructive entries the
agent must show the dry-run to the human and get confirmation before adding the force flag.
