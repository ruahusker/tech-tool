<#
.SYNOPSIS
    One-page system overview: OS, hardware, BIOS, uptime, domain status.
.DESCRIPTION
    Read-only. First script to run on any unknown machine. No admin required.
.PARAMETER OutFile
    Optional path to also save the report as text.
.EXAMPLE
    .\Get-SystemReport.ps1
#>
[CmdletBinding()]
param([string]$OutFile)

$report = New-Object System.Text.StringBuilder
function Section($title) { [void]$report.AppendLine(""); [void]$report.AppendLine("=== $title ==="); }
function Line($text) { [void]$report.AppendLine([string]$text) }

$os   = Get-CimInstance Win32_OperatingSystem
$cs   = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1

Section "IDENTITY"
Line "Computer name : $($env:COMPUTERNAME)"
Line "Manufacturer  : $($cs.Manufacturer)"
Line "Model         : $($cs.Model)"
Line "Serial number : $($bios.SerialNumber)"
Line "BIOS version  : $($bios.SMBIOSBIOSVersion) ($(($bios.ReleaseDate)))"

Section "OPERATING SYSTEM"
Line "OS            : $($os.Caption) $($os.OSArchitecture)"
Line "Version/Build : $($os.Version) (build $($os.BuildNumber))"
Line "Install date  : $($os.InstallDate)"
$uptime = (Get-Date) - $os.LastBootUpTime
Line ("Last boot     : {0}  (uptime {1}d {2}h {3}m)" -f $os.LastBootUpTime, $uptime.Days, $uptime.Hours, $uptime.Minutes)
if ($uptime.Days -ge 14) { Line "  [!] Uptime over 14 days - a reboot often clears odd behavior." }

Section "DOMAIN / WORKGROUP"
if ($cs.PartOfDomain) { Line "Domain joined : YES ($($cs.Domain))" } else { Line "Domain joined : NO (workgroup: $($cs.Workgroup))" }
$aad = & dsregcmd /status 2>$null | Select-String "AzureAdJoined"
if ($aad) { Line ("Entra/AzureAD : " + ($aad -replace '\s+', ' ').ToString().Trim()) }
Line "Current user  : $($env:USERDOMAIN)\$($env:USERNAME)"

Section "CPU / MEMORY"
Line "CPU           : $($cpu.Name)"
Line "Cores/Threads : $($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads"
$totalGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$freeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
Line "RAM           : $totalGB GB total, $freeGB GB free"
Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
    Line ("  Slot {0}: {1} GB @ {2} MHz ({3})" -f $_.DeviceLocator, [math]::Round($_.Capacity/1GB), $_.Speed, $_.Manufacturer)
}
if ($freeGB -lt 1.5) { Line "  [!] Low free RAM - check Get-TopProcesses.ps1 for memory hogs." }

Section "GRAPHICS"
Get-CimInstance Win32_VideoController | ForEach-Object {
    Line ("  {0}  (driver {1}, {2})" -f $_.Name, $_.DriverVersion, $_.DriverDate)
}

Section "STORAGE SUMMARY"
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $sizeGB = [math]::Round($_.Size/1GB,1); $freeGB2 = [math]::Round($_.FreeSpace/1GB,1)
    $pct = if ($_.Size) { [math]::Round(($_.FreeSpace/$_.Size)*100) } else { 0 }
    $flag = if ($pct -lt 10) { "  [!] LOW SPACE" } else { "" }
    Line ("  {0}  {1} GB total, {2} GB free ({3}%){4}" -f $_.DeviceID, $sizeGB, $freeGB2, $pct, $flag)
}

Section "PENDING REBOOT"
$pending = @()
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { $pending += "Component Based Servicing" }
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { $pending += "Windows Update" }
if ((Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)) { $pending += "Pending file renames" }
if ($pending.Count) { Line "Reboot pending: YES ($($pending -join ', '))" } else { Line "Reboot pending: No" }

$text = $report.ToString()
Write-Output $text
if ($OutFile) { $text | Out-File -FilePath $OutFile -Encoding utf8; Write-Output "`nSaved to: $OutFile" }
