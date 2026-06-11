<#
.SYNOPSIS
    Disk health check: SMART status, volume health, free space, recent disk errors.
.DESCRIPTION
    Read-only. Run this early for any "slow computer", "freezing", or boot-issue complaint.
    SMART predictive-failure data needs admin; everything else works without it.
.PARAMETER EventHours
    How many hours back to scan the System event log for disk errors (default 168 = 7 days).
#>
[CmdletBinding()]
param([int]$EventHours = 168)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Output "=== PHYSICAL DISKS ==="
Get-PhysicalDisk | ForEach-Object {
    $flag = if ($_.HealthStatus -ne "Healthy") { "  [!] ATTENTION" } else { "" }
    Write-Output ("  {0}  {1}  {2}  {3} GB  Health: {4}{5}" -f $_.DeviceId, $_.FriendlyName, $_.MediaType, [math]::Round($_.Size/1GB), $_.HealthStatus, $flag)
}

Write-Output "`n=== SMART PREDICTIVE FAILURE ==="
if ($isAdmin) {
    try {
        $smart = Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop
        foreach ($s in $smart) {
            $verdict = if ($s.PredictFailure) { "[!] FAILURE PREDICTED - back up and replace this drive" } else { "OK" }
            Write-Output ("  {0} : {1}" -f ($s.InstanceName -split '_')[0], $verdict)
        }
    } catch { Write-Output "  SMART WMI query not supported on this storage driver (common on NVMe/RAID)." }
    try {
        Get-PhysicalDisk | Get-StorageReliabilityCounter -ErrorAction Stop | ForEach-Object {
            Write-Output ("  Disk {0}: Temp {1}C, ReadErrors {2}, Wear {3}%" -f $_.DeviceId, $_.Temperature, $_.ReadErrorsTotal, $_.Wear)
        }
    } catch { }
} else {
    Write-Output "  (run elevated for SMART predictive-failure and wear data)"
}

Write-Output "`n=== VOLUMES ==="
Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object {
    $pct = if ($_.Size) { [math]::Round(($_.SizeRemaining/$_.Size)*100) } else { 0 }
    $flag = if ($pct -lt 10 -and $_.DriveType -eq 'Fixed') { "  [!] LOW SPACE" } elseif ($_.HealthStatus -ne 'Healthy') { "  [!] $($_.HealthStatus)" } else { "" }
    Write-Output ("  {0}: [{1}] {2}  {3} GB free of {4} GB ({5}%)  Health: {6}{7}" -f $_.DriveLetter, $_.FileSystemType, $_.DriveType, [math]::Round($_.SizeRemaining/1GB,1), [math]::Round($_.Size/1GB,1), $pct, $_.HealthStatus, $flag)
}

Write-Output "`n=== DIRTY BIT (filesystem needs chkdsk?) ==="
Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | ForEach-Object {
    $dirty = & fsutil dirty query "$($_.DriveLetter):" 2>$null
    if ($dirty) { Write-Output "  $dirty" }
}

Write-Output "`n=== RECENT DISK ERRORS (System log, last $EventHours h) ==="
$diskEventIds = 7, 11, 51, 52, 55, 98, 129, 153, 157
try {
    $events = Get-WinEvent -FilterHashtable @{ LogName='System'; Id=$diskEventIds; StartTime=(Get-Date).AddHours(-$EventHours) } -ErrorAction Stop |
        Select-Object -First 30
    if ($events) {
        $events | Group-Object Id | ForEach-Object {
            $sample = $_.Group[0]
            Write-Output ("  [{0}x] Event {1} ({2}): {3}" -f $_.Count, $sample.Id, $sample.ProviderName, ($sample.Message -split "`n")[0])
        }
        Write-Output "  [!] Disk-layer errors found. Correlate with SMART above; suspect cable/drive if Event 7/51/153."
    }
} catch { Write-Output "  No disk-related errors found. Good sign." }

Write-Output "`nHints: chkdsk requires a reboot for the system volume: 'chkdsk C: /f'. For failing SMART, image the drive before anything else."
