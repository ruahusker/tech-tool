## TechKit script catalog (windows)

Run with: powershell -ExecutionPolicy Bypass -File "__TECHKIT__\windows\<Script>" [params]
Full details per script: read __CATALOG__ or the script's own help header.

- Get-SystemReport.ps1 — One-page overview: OS, hardware, BIOS/serial, RAM slots, uptime, domain join, disk summary, pending reboot. Use for: first look at any machine; need serial/model/specs; is it domain joined. | args: -OutFile
- Get-DiskHealth.ps1 — SMART status, volume health, free space, dirty bit, disk errors from the System event log. Use for: slow computer; freezing; clicking noises. | args: -EventHours
- Get-TopProcesses.ps1 — Top CPU and memory consumers (sampled), memory/pagefile pressure. Use for: computer is slow right now; fan always running; out of memory errors. | args: -SampleSeconds -Top
- Get-StartupItems.ps1 — Run keys, startup folders, logon scheduled tasks, auto-services that are stopped, WMI startup inventory. Use for: slow startup; popups at login; suspected unwanted software persistence.
- Get-NetworkDiagnostics.ps1 — Layered check: adapters, IP/DHCP, gateway ping, internet by IP, DNS, HTTP/captive portal, proxy, Wi-Fi signal. Use for: no internet; intermittent connection; only some sites work.
- Test-Connectivity.ps1 — Targeted test to one host: DNS, ping, TCP port, optional traceroute. Use for: can't reach a specific server/printer/share; app cannot connect to backend. | args: -Target* -Port -TraceRoute
- Get-EventLogSummary.ps1 — Groups recent System/Application errors by source; lists distinct errors; flags BSODs, app crashes, dirty shutdowns. Use for: random crashes/reboots; blue screens; app keeps crashing. | args: -Hours -Top
- Export-EventLogs.ps1 — Export System/Application(/Security if admin) .evtx plus systeminfo/ipconfig/hotfixes to the USB collections folder. Use for: need to take evidence away for analysis; escalating to another team. | args: -Destination
- Get-WindowsUpdateStatus.ps1 — Build/UBR, recent hotfixes, WU agent history with failures flagged, WU services, pending reboot, free space. Use for: updates keep failing; is this machine patched; stuck on old build.
- Get-SecurityStatus.ps1 — AV state, firewall profiles, BitLocker, UAC, local admins, RDP/WinRM, SMBv1, SecureBoot/TPM. Use for: security audit; suspected infection; compliance check.
- Get-UserAccountReport.ps1 — Local users with last logon and password age, who is logged on, profile folder sizes, Administrators members. Use for: account audit; before deleting/disabling users; who uses this machine. | args: -SkipProfileSizes
- Remove-InactiveUsers.ps1 [DESTRUCTIVE-dry-runs-first,needs-admin] — Disable (default) or delete local users inactive N days. Dry-run unless -Force. Admin accounts are NEVER touched (no override). Also protects built-ins and the current user. Use for: clean up shared/lab machine accounts; remove departed-user local accounts. | args: -DaysInactive -Delete -RemoveProfile -IncludeNeverLoggedOn -Exclude -Force
- Find-LargeFiles.ps1 — Largest files, first-level folder sizes, known hogs (WU cache, hiberfil, Windows.old, recycle bin). Use for: disk full; what is using all the space. | args: -Path -Top -MinSizeMB
- Clear-TempFiles.ps1 [DESTRUCTIVE-dry-runs-first] — Clean temp folders, WER queue, optionally WU download cache and Recycle Bin. Dry-run unless -Force. Use for: free up disk space quickly; before feature update on a full disk. | args: -IncludeWindowsUpdate -IncludeRecycleBin -Force
- Get-InstalledSoftware.ps1 — Registry-based app inventory (64/32-bit/per-user) with install dates. -SortByDate finds 'what changed last week'. Use for: what's installed; did something install right before the problem started; license audit. | args: -Search -SortByDate
- Get-PrinterDiagnostics.ps1 — Spooler state, printers/ports/drivers, stuck jobs. -ClearQueue purges the queue (admin). Use for: can't print; print job stuck; printer offline. | args: -ClearQueue -RestartSpooler
- Get-BatteryReport.ps1 — Battery health: design vs full-charge capacity, cycle count; generates HTML report. Skips desktops. Use for: laptop battery drains fast; won't hold charge; shuts off at 30%.
- Repair-SystemFiles.ps1 [needs-admin] — DISM + SFC. Default diagnoses only; -Repair runs RestoreHealth + scannow (15-60 min). Use for: Windows Update failures; missing DLL / corrupt system file errors; start menu/explorer corruption. | args: -Repair
- Invoke-TriageSnapshot.ps1 — Runs all read-only diagnostics + raw extras (ipconfig, netstat, drivers, tasks), saves+zips to USB collections. Use for: unknown problem - collect everything first; intermittent issue to analyze later; gather evidence for the AI to analyze. | args: -OutDir
