<#
.SYNOPSIS
    Everything that runs at boot/logon: Run keys, startup folders, logon tasks, auto services.
.DESCRIPTION
    Read-only. The go-to script for "slow startup" and for spotting suspicious persistence.
    Flags auto-start services that are currently stopped (often the cause of "X stopped working").
#>
[CmdletBinding()]
param()

Write-Output "=== REGISTRY RUN KEYS ==="
$runKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
)
foreach ($key in $runKeys) {
    if (Test-Path $key) {
        $props = Get-ItemProperty $key
        $names = $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }
        if ($names) {
            Write-Output "  [$key]"
            $names | ForEach-Object { Write-Output ("    {0} = {1}" -f $_.Name, $_.Value) }
        }
    }
}

Write-Output "`n=== STARTUP FOLDERS ==="
$folders = @(
    [Environment]::GetFolderPath('Startup'),
    [Environment]::GetFolderPath('CommonStartup')
)
foreach ($f in $folders) {
    $items = Get-ChildItem $f -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }
    if ($items) { Write-Output "  [$f]"; $items | ForEach-Object { Write-Output "    $($_.Name)" } }
}

Write-Output "`n=== SCHEDULED TASKS (logon/boot triggers, non-Microsoft) ==="
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskPath -notlike "\Microsoft\*" -and $_.State -ne 'Disabled' -and
    ($_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'LogonTrigger|BootTrigger' })
} | ForEach-Object {
    $action = ($_.Actions | Select-Object -First 1).Execute
    Write-Output ("  {0}{1}  ->  {2}" -f $_.TaskPath, $_.TaskName, $action)
}

Write-Output "`n=== AUTO-START SERVICES CURRENTLY STOPPED ==="
$stopped = Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" |
    Where-Object { $_.Name -notmatch '^(sppsvc|RemoteRegistry|MapsBroker|WbioSrvc|gpsvc|TrustedInstaller|edgeupdate|gupdate|GoogleUpdater|MicrosoftEdgeElevation|wuauserv|dcsvc|BITS)' }
if ($stopped) {
    $stopped | ForEach-Object { Write-Output ("  [!] {0} ({1}) - {2}, exit code {3}" -f $_.DisplayName, $_.Name, $_.State, $_.ExitCode) }
    Write-Output "  These are set to start automatically but are not running. Check if intentional."
} else { Write-Output "  None of note - all auto services running." }

Write-Output "`n=== WMI STARTUP COMMAND INVENTORY ==="
Get-CimInstance Win32_StartupCommand | ForEach-Object {
    Write-Output ("  [{0}] {1}: {2}" -f $_.Location, $_.Name, $_.Command)
}

Write-Output "`nHint: to disable an item, prefer Task Manager > Startup tab (reversible) over deleting registry values."
