<#
.SYNOPSIS
    Printer troubleshooting: spooler state, installed printers, stuck jobs; optional queue clear.
.DESCRIPTION
    Read-only by default. -ClearQueue and -RestartSpooler change state (admin needed).
.PARAMETER ClearQueue
    Delete all queued jobs (the classic fix for a jammed queue).
.PARAMETER RestartSpooler
    Restart the Print Spooler service.
.EXAMPLE
    .\Get-PrinterDiagnostics.ps1
    .\Get-PrinterDiagnostics.ps1 -ClearQueue -RestartSpooler
#>
[CmdletBinding()]
param([switch]$ClearQueue, [switch]$RestartSpooler)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Output "=== PRINT SPOOLER SERVICE ==="
$spooler = Get-Service Spooler
Write-Output ("  Status: {0}  StartType: {1}" -f $spooler.Status, $spooler.StartType)
if ($spooler.Status -ne 'Running') { Write-Output "  [!] Spooler not running - nothing will print until it is." }

Write-Output "`n=== PRINTERS ==="
$default = (Get-CimInstance Win32_Printer -Filter "Default=TRUE").Name
Get-Printer -ErrorAction SilentlyContinue | ForEach-Object {
    $tag = if ($_.Name -eq $default) { " (DEFAULT)" } else { "" }
    $flag = if ($_.PrinterStatus -notin 'Normal','Idle') { "  [!]" } else { "" }
    Write-Output ("  {0,-35} {1,-12} Port: {2,-20} Driver: {3}{4}{5}" -f $_.Name, $_.PrinterStatus, $_.PortName, $_.DriverName, $tag, $flag)
}

Write-Output "`n=== QUEUED JOBS ==="
$anyJobs = $false
Get-Printer -ErrorAction SilentlyContinue | ForEach-Object {
    $jobs = Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue
    foreach ($j in $jobs) {
        $anyJobs = $true
        $age = [int]((Get-Date) - $j.SubmittedTime).TotalMinutes
        $flag = if ($j.JobStatus -match 'Error|Offline' -or $age -gt 30) { "  [!] stuck?" } else { "" }
        Write-Output ("  [{0}] job {1}: '{2}' by {3} - {4}, {5} min old{6}" -f $_.Name, $j.Id, $j.DocumentName, $j.UserName, $j.JobStatus, $age, $flag)
    }
}
if (-not $anyJobs) { Write-Output "  No jobs queued." }

if ($ClearQueue) {
    if (-not $isAdmin) { Write-Output "`n[!] -ClearQueue needs an elevated shell."; exit 1 }
    Write-Output "`n=== CLEARING QUEUES ==="
    Get-Printer | ForEach-Object { Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue | Remove-PrintJob -ErrorAction SilentlyContinue }
    # Anything left means spooler files are locked - force-clean the spool folder
    $remaining = Get-Printer | ForEach-Object { Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue }
    if ($remaining) {
        Write-Output "  Jobs locked; stopping spooler and purging spool folder..."
        Stop-Service Spooler -Force
        Remove-Item "$env:windir\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
        Start-Service Spooler
        Write-Output "  Spool folder purged, spooler restarted."
    } else { Write-Output "  All jobs removed." }
}

if ($RestartSpooler -and -not $ClearQueue) {
    if (-not $isAdmin) { Write-Output "`n[!] -RestartSpooler needs an elevated shell."; exit 1 }
    Write-Output "`nRestarting spooler..."
    Restart-Service Spooler -Force
    Write-Output "  Spooler: $((Get-Service Spooler).Status)"
}

Write-Output "`nHints: test page bypassing app: 'rundll32 printui.dll,PrintUIEntry /k /n \"PRINTER\"'. For network printers, Test-Connectivity.ps1 -Target <ip> -Port 9100."
