<#
.SYNOPSIS
    Export Windows event logs (.evtx) to a folder, default on the USB drive, for offline analysis.
.DESCRIPTION
    Read-only with respect to the machine. Security log export requires admin.
.PARAMETER Destination
    Output folder. Default: <this drive>\TechKit\collections\<hostname>-logs-<timestamp>
.PARAMETER Logs
    Logs to export. Default: System, Application, plus Security when elevated.
#>
[CmdletBinding()]
param(
    [string]$Destination,
    [string[]]$Logs
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $Logs) {
    $Logs = @('System','Application')
    if ($isAdmin) { $Logs += 'Security' } else { Write-Output "(not elevated - skipping Security log)" }
}

if (-not $Destination) {
    $driveRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $Destination = Join-Path $driveRoot ("TechKit\collections\{0}-logs-{1}" -f $env:COMPUTERNAME, $stamp)
}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null

foreach ($log in $Logs) {
    $file = Join-Path $Destination ("{0}.evtx" -f ($log -replace '[\\/]','-'))
    & wevtutil epl $log $file 2>&1 | Out-Null
    if (Test-Path $file) {
        Write-Output ("  Exported {0,-14} -> {1}  ({2} MB)" -f $log, $file, [math]::Round((Get-Item $file).Length/1MB,1))
    } else {
        Write-Output "  [!] Failed to export $log"
    }
}

# A few high-value extras alongside the evtx files
& systeminfo 2>$null | Out-File (Join-Path $Destination "systeminfo.txt") -Encoding utf8
& ipconfig /all 2>$null | Out-File (Join-Path $Destination "ipconfig-all.txt") -Encoding utf8
Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending |
    Out-File (Join-Path $Destination "hotfixes.txt") -Encoding utf8

Write-Output "`nDone: $Destination"
Write-Output "Open .evtx files on any Windows machine with Event Viewer (Action > Open Saved Log)."
