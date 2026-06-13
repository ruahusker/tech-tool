<#
.SYNOPSIS
    Crash & BSOD report: blue-screen bugcheck codes, unexpected shutdowns, app crashes, and
    minidump files. Read-only.
.DESCRIPTION
    For "random reboots", "blue screens", "it just crashes". Pulls BugCheck (BSOD) events with
    their stop codes, Kernel-Power 41 / EventLog 6008 unexpected shutdowns, application crash
    events, and lists the minidump files on disk so you can grab them for deeper analysis.
.PARAMETER Days
    How far back to look (default 14).
#>
[CmdletBinding()]
param([int]$Days = 14)

$since = (Get-Date).AddDays(-$Days)
Write-Output "=== Crash & BSOD Report ==="
Write-Output ("Host: {0}  |  Since: {1:yyyy-MM-dd}" -f $env:COMPUTERNAME, $since)

Write-Output "`n=== Blue Screens (BugCheck) ==="
$bc = @()
try { $bc = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; StartTime=$since} -ErrorAction Stop) } catch {}
if ($bc.Count -eq 0) {
    try { $bc = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001; StartTime=$since} -ErrorAction Stop | Where-Object { $_.Message -match 'bugcheck' }) } catch {}
}
if ($bc.Count -gt 0) {
    foreach ($e in $bc) { Write-Output ("  [!] {0:yyyy-MM-dd HH:mm}  {1}" -f $e.TimeCreated, (($e.Message -replace '\s+',' ').Trim())) }
} else { Write-Output "  None recorded." }

Write-Output "`n=== Unexpected Shutdowns (Kernel-Power 41 / EventLog 6008) ==="
$kp = @()
try { $kp = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=41,6008; StartTime=$since} -ErrorAction Stop) } catch {}
if ($kp.Count -gt 0) {
    $kp | Select-Object -First 10 | ForEach-Object { Write-Output ("  [!] {0:yyyy-MM-dd HH:mm}  Id {1}  {2}" -f $_.TimeCreated, $_.Id, $_.ProviderName) }
    Write-Output ("  ({0} unexpected-shutdown event(s); often power loss, overheating, or a hard hang.)" -f $kp.Count)
} else { Write-Output "  None recorded." }

Write-Output "`n=== Application Crashes (Application Error 1000) ==="
$ac = @()
try { $ac = @(Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=$since} -ErrorAction Stop) } catch {}
if ($ac.Count -gt 0) {
    $ac | Group-Object { ($_.Message -split "`n")[0] } | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object {
        Write-Output ("  {0,3}x  {1}" -f $_.Count, (($_.Name -replace '\s+',' ').Trim()))
    }
} else { Write-Output "  None recorded." }

Write-Output "`n=== Minidump Files ==="
$dumpDir = Join-Path $env:SystemRoot "Minidump"
if (Test-Path $dumpDir) {
    $dumps = @(Get-ChildItem $dumpDir -Filter *.dmp -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($dumps.Count -gt 0) {
        Write-Output ("  {0} dump(s) in {1}:" -f $dumps.Count, $dumpDir)
        $dumps | Select-Object -First 10 | ForEach-Object { Write-Output ("    {0:yyyy-MM-dd HH:mm}  {1}  ({2:N0} KB)" -f $_.LastWriteTime, $_.Name, ($_.Length/1KB)) }
        Write-Output "  Tip: open the newest .dmp in WinDbg or BlueScreenView for the faulting driver."
    } else { Write-Output "  Folder exists but no .dmp files." }
} else {
    Write-Output ("  No minidump folder ({0})." -f $dumpDir)
    $cd = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name CrashDumpEnabled -ErrorAction SilentlyContinue).CrashDumpEnabled
    if ($cd -eq 0) { Write-Output "  [!] Crash dump creation is DISABLED - enable it to capture the next BSOD." }
}

$full = Join-Path $env:SystemRoot "MEMORY.DMP"
if (Test-Path $full) { $f = Get-Item $full; Write-Output ("`n  Full dump: {0}  {1:yyyy-MM-dd HH:mm}  ({2:N0} MB)" -f $full, $f.LastWriteTime, ($f.Length/1MB)) }
