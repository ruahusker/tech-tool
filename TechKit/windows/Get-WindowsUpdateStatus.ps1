<#
.SYNOPSIS
    Windows Update health: recent updates, update history, service state, pending reboot.
.DESCRIPTION
    Read-only. Run for "updates keep failing" or to verify patch level during any visit.
#>
[CmdletBinding()]
param([int]$HistoryCount = 15)

Write-Output "=== OS BUILD ==="
$os = Get-CimInstance Win32_OperatingSystem
$ubr = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).UBR
$disp = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue).DisplayVersion
Write-Output "  $($os.Caption) $disp  build $($os.BuildNumber).$ubr"

Write-Output "`n=== RECENT HOTFIXES (Get-HotFix) ==="
Get-HotFix | Sort-Object { if ($_.InstalledOn) { $_.InstalledOn } else { [datetime]::MinValue } } -Descending |
    Select-Object -First 10 | ForEach-Object {
    Write-Output ("  {0}  {1,-12} {2}" -f $_.HotFixID, $_.Description, $_.InstalledOn)
}

Write-Output "`n=== UPDATE HISTORY (Windows Update agent, last $HistoryCount) ==="
try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $count = [math]::Min($searcher.GetTotalHistoryCount(), $HistoryCount)
    if ($count -gt 0) {
        $searcher.QueryHistory(0, $count) | ForEach-Object {
            $result = switch ($_.ResultCode) { 2 {"OK     "} 3 {"OK(warn)"} 4 {"FAILED "} 5 {"ABORTED"} default {"code $($_.ResultCode)"} }
            $title = $_.Title; if ($title.Length -gt 90) { $title = $title.Substring(0,90) + "..." }
            $flag = if ($_.ResultCode -eq 4) { " [!]" } else { "" }
            Write-Output ("  {0:yyyy-MM-dd}  {1} {2}{3}" -f $_.Date, $result, $title, $flag)
        }
    } else { Write-Output "  No history entries returned." }
} catch { Write-Output "  Could not query update history COM API: $($_.Exception.Message)" }

Write-Output "`n=== SERVICES ==="
foreach ($svc in 'wuauserv','BITS','cryptsvc','TrustedInstaller','UsoSvc') {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s) { Write-Output ("  {0,-18} {1,-10} (start: {2})" -f $s.Name, $s.Status, $s.StartType) }
}

Write-Output "`n=== PENDING REBOOT ==="
$pending = @()
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { $pending += "CBS" }
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { $pending += "WindowsUpdate" }
if ($pending) { Write-Output "  [!] Reboot pending ($($pending -join ', ')) - updates may be stuck until reboot." }
else { Write-Output "  None." }

Write-Output "`n=== FREE SPACE ON SYSTEM DRIVE ==="
$sys = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
$freeGB = [math]::Round($sys.FreeSpace/1GB,1)
Write-Output "  $($env:SystemDrive) $freeGB GB free"
if ($freeGB -lt 20) { Write-Output "  [!] Feature updates typically need 20+ GB free. Run Clear-TempFiles.ps1 / Find-LargeFiles.ps1." }

Write-Output "`nHints for stuck updates: reboot first; then 'sfc /scannow' + DISM (Repair-SystemFiles.ps1 -Repair);"
Write-Output "last resort: stop wuauserv+BITS, rename C:\Windows\SoftwareDistribution, restart services."
