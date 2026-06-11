<#
.SYNOPSIS
    Find CPU and memory hogs. Two-sample CPU measurement (locale-safe, no perf counter names).
.DESCRIPTION
    Read-only. Run for "computer is slow" complaints. Samples CPU over an interval,
    then reports top consumers by CPU and by memory, plus system memory pressure.
.PARAMETER SampleSeconds
    CPU sampling window (default 5).
.PARAMETER Top
    How many processes to show per list (default 12).
#>
[CmdletBinding()]
param([int]$SampleSeconds = 5, [int]$Top = 12)

$logicalCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors

Write-Output "Sampling CPU for $SampleSeconds seconds..."
$s1 = @{}
Get-Process | ForEach-Object { $s1[$_.Id] = $_.TotalProcessorTime.TotalMilliseconds }
Start-Sleep -Seconds $SampleSeconds
$results = foreach ($p in Get-Process) {
    if ($s1.ContainsKey($p.Id)) {
        $deltaMs = $p.TotalProcessorTime.TotalMilliseconds - $s1[$p.Id]
        $cpuPct = [math]::Round(($deltaMs / ($SampleSeconds * 1000) / $logicalCores) * 100, 1)
        [PSCustomObject]@{ Name=$p.ProcessName; Id=$p.Id; CPUPct=$cpuPct; MemMB=[math]::Round($p.WorkingSet64/1MB) }
    }
}

Write-Output "`n=== TOP BY CPU (% of all cores) ==="
$results | Sort-Object CPUPct -Descending | Select-Object -First $Top | ForEach-Object {
    Write-Output ("  {0,5}%  {1,8} MB  {2} (pid {3})" -f $_.CPUPct, $_.MemMB, $_.Name, $_.Id)
}

Write-Output "`n=== TOP BY MEMORY ==="
$results | Sort-Object MemMB -Descending | Select-Object -First $Top | ForEach-Object {
    Write-Output ("  {0,8} MB  {1,5}%  {2} (pid {3})" -f $_.MemMB, $_.CPUPct, $_.Name, $_.Id)
}

$os = Get-CimInstance Win32_OperatingSystem
$totalMB = [math]::Round($os.TotalVisibleMemorySize/1KB)
$freeMB  = [math]::Round($os.FreePhysicalMemory/1KB)
$usedPct = [math]::Round((($totalMB-$freeMB)/$totalMB)*100)
Write-Output "`n=== MEMORY PRESSURE ==="
Write-Output "  Physical: $usedPct% used ($freeMB MB free of $totalMB MB)"
$page = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
if ($page) { $page | ForEach-Object { Write-Output ("  Pagefile {0}: {1} MB in use (peak {2} MB)" -f $_.Name, $_.CurrentUsage, $_.PeakUsage) } }
if ($usedPct -gt 90) { Write-Output "  [!] Memory exhausted - close apps, check for memory leak in top list, or add RAM." }

Write-Output "`n=== PROCESS COUNT ==="
Write-Output ("  {0} processes, {1} total threads" -f (Get-Process).Count, ((Get-Process | Measure-Object Threads -Sum).Sum))
