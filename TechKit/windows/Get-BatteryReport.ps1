<#
.SYNOPSIS
    Laptop battery health: design vs current capacity, cycle count, recent drain.
.DESCRIPTION
    Read-only. Uses powercfg's XML battery report. Skips cleanly on desktops.
#>
[CmdletBinding()]
param()

$bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
if (-not $bat) { Write-Output "No battery detected - this appears to be a desktop. Nothing to do."; exit 0 }

Write-Output "=== LIVE STATUS ==="
foreach ($b in $bat) {
    $status = switch ($b.BatteryStatus) { 1 {"Discharging"} 2 {"On AC"} 3 {"Fully charged"} 4 {"Low"} 5 {"Critical"} 6 {"Charging"} default {"code $($b.BatteryStatus)"} }
    Write-Output ("  Charge: {0}%  Status: {1}" -f $b.EstimatedChargeRemaining, $status)
}

$xml = Join-Path $env:TEMP "battery-report.xml"
& powercfg /batteryreport /xml /output $xml 2>&1 | Out-Null
if (-not (Test-Path $xml)) { Write-Output "`npowercfg battery report unavailable (needs a real battery driver)."; exit 0 }

try {
    [xml]$r = Get-Content $xml
    $ns = @{ bm = $r.BatteryReport.NamespaceURI }
    $batteries = $r.BatteryReport.Batteries.Battery
    Write-Output "`n=== BATTERY HEALTH ==="
    foreach ($b in $batteries) {
        $design = [long]$b.DesignCapacity
        $full   = [long]$b.FullChargeCapacity
        $health = if ($design) { [math]::Round(($full/$design)*100) } else { 0 }
        Write-Output ("  Battery       : {0} {1}" -f $b.Manufacturer, $b.Id)
        Write-Output ("  Design cap    : {0:N0} mWh" -f $design)
        Write-Output ("  Full-charge   : {0:N0} mWh" -f $full)
        Write-Output ("  Health        : {0}% of design" -f $health)
        Write-Output ("  Cycle count   : {0}" -f $b.CycleCount)
        if ($health -lt 60) { Write-Output "  [!] Below 60% of design capacity - recommend battery replacement." }
        elseif ($health -lt 80) { Write-Output "  [~] Worn (60-80%) - noticeably reduced runtime is expected." }
    }
} catch {
    Write-Output "Could not parse XML report: $($_.Exception.Message)"
}

# Human-readable HTML report for handing to the customer
$html = Join-Path $env:TEMP "battery-report.html"
& powercfg /batteryreport /output $html 2>&1 | Out-Null
if (Test-Path $html) { Write-Output "`nFull HTML report (drain history, usage graphs): $html" }
Remove-Item $xml -ErrorAction SilentlyContinue
