<#
.SYNOPSIS
    Summarize recent errors/warnings from System and Application logs; flag crashes and dirty shutdowns.
.DESCRIPTION
    Read-only. The fastest way to see what has been going wrong on a machine. Groups noise
    by source so patterns stand out, then lists the most recent distinct errors.
.PARAMETER Hours
    Look-back window (default 48).
.PARAMETER Top
    Max distinct recent errors to print per log (default 15).
#>
[CmdletBinding()]
param([int]$Hours = 48, [int]$Top = 15)

$start = (Get-Date).AddHours(-$Hours)

foreach ($log in 'System','Application') {
    Write-Output "=== $log LOG - errors/warnings in last $Hours h ==="
    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName=$log; Level=1,2,3; StartTime=$start } -ErrorAction Stop
    } catch { Write-Output "  None found.`n"; continue }

    Write-Output "  -- Top sources --"
    $events | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
        Write-Output ("  {0,5}x  {1}" -f $_.Count, $_.Name)
    }

    Write-Output "  -- Most recent distinct errors --"
    $seen = @{}
    foreach ($e in ($events | Where-Object Level -le 2)) {
        $key = "$($e.ProviderName)|$($e.Id)"
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $msg = if ($e.Message) { ($e.Message -split "`n")[0].Trim() } else { "(no message)" }
            if ($msg.Length -gt 130) { $msg = $msg.Substring(0,130) + "..." }
            Write-Output ("  {0:MM-dd HH:mm}  [{1}/{2}] {3}" -f $e.TimeCreated, $e.ProviderName, $e.Id, $msg)
            if ($seen.Count -ge $Top) { break }
        }
    }
    Write-Output ""
}

Write-Output "=== CRASH / STABILITY MARKERS (last $Hours h) ==="
$markers = @(
    @{ Id=41;   Log='System';      Note='Kernel-Power: machine lost power or hard-froze (dirty shutdown)' },
    @{ Id=6008; Log='System';      Note='Unexpected shutdown' },
    @{ Id=1001; Log='System';      Note='BugCheck: blue screen occurred' },
    @{ Id=1000; Log='Application'; Note='Application crash' },
    @{ Id=1002; Log='Application'; Note='Application hang' }
)
$found = $false
foreach ($m in $markers) {
    try {
        $hits = Get-WinEvent -FilterHashtable @{ LogName=$m.Log; Id=$m.Id; StartTime=$start } -ErrorAction Stop
        if ($hits) {
            $found = $true
            Write-Output ("  [!] {0}x Event {1}: {2}" -f $hits.Count, $m.Id, $m.Note)
            if ($m.Id -in 1000,1002) {
                $hits | Select-Object -First 5 | ForEach-Object {
                    $app = ($_.Message -split "`n")[0..2] -join ' '
                    Write-Output ("       {0:MM-dd HH:mm}  {1}" -f $_.TimeCreated, $app.Substring(0, [math]::Min(110, $app.Length)))
                }
            }
        }
    } catch { }
}
if (-not $found) { Write-Output "  None - no crashes, hangs, BSODs, or dirty shutdowns in window. " }

Write-Output "`nHint: widen with -Hours 168 for intermittent issues; use Export-EventLogs.ps1 to take logs with you."
