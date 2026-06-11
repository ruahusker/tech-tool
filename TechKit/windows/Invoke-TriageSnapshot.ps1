<#
.SYNOPSIS
    One-shot triage: run every read-only diagnostic and save all output to a timestamped
    folder (default: this USB drive's TechKit\collections). The "grab everything" button.
.DESCRIPTION
    Read-only. Run this first on a problem machine when you don't yet know what's wrong,
    or when you need evidence to analyze later (or to feed to the AI assistant).
    Takes ~2-5 minutes. Skips the slow full-disk file scan.
.PARAMETER OutDir
    Where to write the snapshot folder.
#>
[CmdletBinding()]
param([string]$OutDir)

if (-not $OutDir) {
    $driveRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $OutDir = Join-Path $driveRoot "TechKit\collections"
}
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$dest = Join-Path $OutDir ("{0}-triage-{1}" -f $env:COMPUTERNAME, $stamp)
New-Item -ItemType Directory -Path $dest -Force | Out-Null

Write-Output "Triage snapshot -> $dest`n"

$jobs = @(
    @{ Name = "system-report";    Script = "Get-SystemReport.ps1";        Args = @{} }
    @{ Name = "disk-health";      Script = "Get-DiskHealth.ps1";          Args = @{} }
    @{ Name = "top-processes";    Script = "Get-TopProcesses.ps1";        Args = @{ SampleSeconds = 5 } }
    @{ Name = "startup-items";    Script = "Get-StartupItems.ps1";        Args = @{} }
    @{ Name = "network";          Script = "Get-NetworkDiagnostics.ps1";  Args = @{} }
    @{ Name = "event-summary";    Script = "Get-EventLogSummary.ps1";     Args = @{ Hours = 72 } }
    @{ Name = "update-status";    Script = "Get-WindowsUpdateStatus.ps1"; Args = @{} }
    @{ Name = "security-status";  Script = "Get-SecurityStatus.ps1";      Args = @{} }
    @{ Name = "user-accounts";    Script = "Get-UserAccountReport.ps1";   Args = @{ SkipProfileSizes = $true } }
    @{ Name = "installed-apps";   Script = "Get-InstalledSoftware.ps1";   Args = @{ SortByDate = $true } }
    @{ Name = "battery";          Script = "Get-BatteryReport.ps1";       Args = @{} }
    @{ Name = "printers";         Script = "Get-PrinterDiagnostics.ps1";  Args = @{} }
)

foreach ($j in $jobs) {
    $path = Join-Path $PSScriptRoot $j.Script
    if (-not (Test-Path $path)) { Write-Output "  skip $($j.Script) (not found)"; continue }
    Write-Output ("  running {0} ..." -f $j.Script)
    try {
        $splat = $j.Args
        & $path @splat *>&1 | Out-File (Join-Path $dest "$($j.Name).txt") -Encoding utf8
    } catch {
        "ERROR: $($_.Exception.Message)" | Out-File (Join-Path $dest "$($j.Name).txt") -Encoding utf8
    }
}

# Raw command output that complements the scripts
Write-Output "  collecting raw extras ..."
& ipconfig /all          2>$null | Out-File (Join-Path $dest "raw-ipconfig.txt")  -Encoding utf8
& route print            2>$null | Out-File (Join-Path $dest "raw-routes.txt")    -Encoding utf8
& netstat -ano           2>$null | Select-Object -First 200 | Out-File (Join-Path $dest "raw-netstat.txt") -Encoding utf8
& tasklist /svc          2>$null | Out-File (Join-Path $dest "raw-tasklist.txt")  -Encoding utf8
& driverquery /v /fo csv 2>$null | Out-File (Join-Path $dest "raw-drivers.csv")   -Encoding utf8
& schtasks /query /fo csv 2>$null | Out-File (Join-Path $dest "raw-schtasks.csv") -Encoding utf8

# Manifest so the snapshot is self-describing
@"
Triage snapshot
Host      : $env:COMPUTERNAME
User      : $env:USERDOMAIN\$env:USERNAME
Taken     : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Elevated  : $(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Kit       : TechKit windows
"@ | Out-File (Join-Path $dest "MANIFEST.txt") -Encoding utf8

$zip = "$dest.zip"
try {
    Compress-Archive -Path $dest -DestinationPath $zip -Force
    Write-Output "`nSnapshot complete: $dest"
    Write-Output "Zipped copy     : $zip"
} catch {
    Write-Output "`nSnapshot complete (zip failed, folder kept): $dest"
}
