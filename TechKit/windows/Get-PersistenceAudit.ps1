<#
.SYNOPSIS
    Autostart & persistence audit: Run keys, Startup folders, scheduled tasks, auto-start
    services, and WMI subscriptions - with suspicious entries flagged. Read-only.
.DESCRIPTION
    A focused look at everything that can run automatically, for malware/PUP cleanup and
    "what keeps coming back". Goes beyond Startup Programs by including non-Microsoft scheduled
    tasks, auto services whose binaries live in user-writable/temp paths, and WMI event
    subscriptions (a common fileless-persistence spot). Entries in Temp/AppData/ProgramData/
    Public or that use a script host are flagged with [!].
#>
[CmdletBinding()]
param()

Write-Output "=== Startup & Persistence Audit ==="
Write-Output ("Host: {0}  |  User: {1}" -f $env:COMPUTERNAME, $env:USERNAME)

function Suspicious($path){
    if (-not $path) { return $false }
    return ($path -match '\\Temp\\|\\AppData\\|\\ProgramData\\|\\Users\\Public\\|\\Downloads\\|powershell|cmd\.exe|mshta|wscript|cscript|rundll32')
}

Write-Output "`n=== Run / RunOnce Keys ==="
$runKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
)
foreach ($k in $runKeys) {
    if (-not (Test-Path $k)) { continue }
    $props = Get-ItemProperty $k -ErrorAction SilentlyContinue
    if ($null -eq $props) { continue }
    $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
        $flag = if (Suspicious $_.Value) { "  [!]" } else { "" }
        Write-Output ("  {0} = {1}{2}" -f $_.Name, $_.Value, $flag)
    }
}

Write-Output "`n=== Startup Folders ==="
$sf = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup")
foreach ($d in $sf) {
    if (Test-Path $d) {
        @(Get-ChildItem $d -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }) | ForEach-Object { Write-Output ("  {0}" -f $_.FullName) }
    }
}

Write-Output "`n=== Non-Microsoft Scheduled Tasks ==="
try {
    Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -ne 'Disabled' } | ForEach-Object {
        $actions = (@($_.Actions | ForEach-Object { $_.Execute }) -join '; ')
        if ($actions -and $actions -notmatch '%windir%|\\Windows\\System32|\\Windows\\') {
            $flag = if (Suspicious $actions) { "  [!]" } else { "" }
            Write-Output ("  {0}{1}  ->  {2}{3}" -f $_.TaskPath, $_.TaskName, $actions, $flag)
        }
    }
} catch { Write-Output "  (Get-ScheduledTask unavailable)" }

Write-Output "`n=== Auto-Start Services (non-Windows path) ==="
Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.StartMode -eq 'Auto' -and $_.PathName } | ForEach-Object {
    if ($_.PathName -notmatch '\\Windows\\') {
        $flag = if (Suspicious $_.PathName) { "  [!]" } else { "" }
        Write-Output ("  {0,-30} {1}{2}" -f $_.Name, $_.PathName, $flag)
    }
}

Write-Output "`n=== WMI Event Subscriptions (fileless persistence) ==="
try {
    $consumers = @(Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer -ErrorAction Stop)
    if ($consumers.Count -gt 0) {
        Write-Output "  [!] WMI event consumers present (review - some management tools use these legitimately):"
        $consumers | ForEach-Object { Write-Output ("    {0}" -f $_.Name) }
    } else { Write-Output "  None." }
} catch { Write-Output "  (could not query WMI subscriptions)" }

Write-Output "`n[i] [!] = lives in a user-writable/temp path or uses a script host. Not proof of malware, but worth a look."
