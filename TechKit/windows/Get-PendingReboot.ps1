<#
.SYNOPSIS
    Detects a pending reboot and shows true uptime (seeing past Fast Startup). Read-only.
.DESCRIPTION
    A huge share of "weird" tickets are really "this machine hasn't actually rebooted in weeks"
    or "an update is half-installed waiting on a reboot". Checks every standard pending-reboot
    flag (Component Servicing, Windows Update, pending file renames, computer rename, ConfigMgr),
    reports last boot time and uptime, and warns when Fast Startup is hiding the fact that
    shutdowns are not real reboots.
#>
[CmdletBinding()]
param()

Write-Output "=== Pending Reboot & Uptime ==="
Write-Output ("Host: {0}" -f $env:COMPUTERNAME)

$os = Get-CimInstance Win32_OperatingSystem
$boot = $os.LastBootUpTime
$up = (Get-Date) - $boot
Write-Output ("Last boot : {0}" -f $boot)
Write-Output ("Uptime    : {0}d {1}h {2}m" -f $up.Days, $up.Hours, $up.Minutes)
if ($up.TotalDays -gt 14) { Write-Output ("  [!] Up for {0:N0} days - a real reboot may clear the issue." -f $up.TotalDays) }

$hb = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
if ($hb -eq 1) { Write-Output "  [!] Fast Startup is ON - a 'Shut down' does NOT fully reboot. Use 'Restart' (or shutdown /r) to truly cycle the kernel." }
elseif ($hb -eq 0) { Write-Output "  Fast Startup: off (shutdown = true cold boot)." }

Write-Output "`n=== Pending Reboot Flags ==="
$script:pending = $false
function Flag($name,$cond){ if ($cond) { Write-Output ("  [!] PENDING: {0}" -f $name); $script:pending = $true } else { Write-Output ("   ok : {0}" -f $name) } }

Flag "Component Based Servicing (CBS)" (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending")
Flag "Windows Update (reboot required)" (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")
$pfr = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
Flag "Pending file rename operations" ([bool]$pfr)
$active = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" -Name ComputerName -ErrorAction SilentlyContinue).ComputerName
$pendName = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" -Name ComputerName -ErrorAction SilentlyContinue).ComputerName
Flag "Computer rename pending" ($active -and $pendName -and ($active -ne $pendName))

try {
    $ccm = Invoke-CimMethod -Namespace "ROOT\ccm\ClientSDK" -ClassName CCM_ClientUtilities -MethodName DetermineIfRebootPending -ErrorAction Stop
    Flag "ConfigMgr (SCCM) client" ($ccm.RebootPending -or $ccm.IsHardRebootPending)
} catch { Write-Output "   -- : ConfigMgr client not present." }

Write-Output ""
if ($script:pending) { Write-Output "[!] A reboot is PENDING. Reboot before troubleshooting further or installing updates." }
else { Write-Output "No pending reboot flags set." }
