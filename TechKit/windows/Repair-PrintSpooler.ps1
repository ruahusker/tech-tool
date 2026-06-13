<#
.SYNOPSIS
    Reset the Windows print spooler: stop the service, clear stuck jobs, restart.
    DRY-RUN BY DEFAULT; requires admin.
.DESCRIPTION
    The classic fix for "stuck print job", "spooler keeps crashing", "printer offline" and
    "can't add printer". Stops the Spooler service, deletes everything in
    %SystemRoot%\System32\spool\PRINTERS (the queued jobs), then restarts the service.
    Pair with Get-PrinterDiagnostics.ps1 to confirm. Use -RestartOnly for a gentle restart
    that does NOT purge queued jobs.
.PARAMETER Force
    Actually perform the reset. Without it, preview only.
.PARAMETER RestartOnly
    Just restart the Spooler service; do not delete queued jobs.
#>
[CmdletBinding()]
param([switch]$Force,[switch]$RestartOnly)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Output "[!] Requires an elevated PowerShell. Aborting."; exit 1 }

$mode = if ($Force) { "EXECUTE" } else { "DRY RUN (add -Force to apply)" }
$spoolDir = Join-Path $env:SystemRoot "System32\spool\PRINTERS"
Write-Output "=== Reset Print Spooler ==="
Write-Output ("Mode: {0}  |  Host: {1}" -f $mode, $env:COMPUTERNAME)

$svc = Get-Service -Name Spooler -ErrorAction SilentlyContinue
if ($svc) { Write-Output ("Spooler service: {0} (StartType {1})" -f $svc.Status, $svc.StartType) }
$jobs = @(Get-ChildItem -Path $spoolDir -File -ErrorAction SilentlyContinue)
Write-Output ("Queued spool files: {0} in {1}" -f $jobs.Count, $spoolDir)
Write-Output ""

function Step($desc,[scriptblock]$act){
    if ($Force) { try { & $act; Write-Output "  OK  : $desc" } catch { Write-Output "  [!] : $desc -> $($_.Exception.Message)" } }
    else { Write-Output "  WOULD: $desc" }
}

Step "stop Spooler service" { Stop-Service -Name Spooler -Force -ErrorAction Stop; Start-Sleep -Seconds 1 }
if (-not $RestartOnly) {
    if ($jobs.Count -gt 0) { Step ("delete {0} queued job file(s)" -f $jobs.Count) { Remove-Item -Path (Join-Path $spoolDir '*') -Force -Recurse -ErrorAction SilentlyContinue } }
    else { Write-Output "  (no queued jobs to clear)" }
} else {
    Write-Output "  (RestartOnly: keeping queued jobs)"
}
Step "set Spooler start type to Automatic" { Set-Service -Name Spooler -StartupType Automatic }
Step "start Spooler service" { Start-Service -Name Spooler -ErrorAction Stop }

Write-Output ""
if ($Force) {
    $now = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    Write-Output ("Spooler is now: {0}" -f $now.Status)
    Write-Output "Done. Verify with Get-PrinterDiagnostics.ps1, then have the user retry the print."
} else {
    Write-Output "Dry run complete. Re-run with -Force. Use -RestartOnly to keep queued jobs."
}
