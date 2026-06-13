<#
.SYNOPSIS
    Microsoft Defender status, threat history, and on-demand scan. Reports by default;
    -Force runs a scan.
.DESCRIPTION
    For suspected infection or a quick health check. Shows real-time protection state,
    signature version/age, last scan times, and any detected threats. -Update refreshes
    signatures; -Force starts a scan (Quick by default, -Full for a full scan). If a third-party
    AV is primary, Defender may be passive - that is reported.
.PARAMETER Force
    Start a scan (Quick unless -Full).
.PARAMETER Full
    Run a full scan instead of quick (can take a long time).
.PARAMETER Update
    Update Defender signatures before scanning/reporting.
#>
[CmdletBinding()]
param([switch]$Force,[switch]$Full,[switch]$Update)

Write-Output "=== Antivirus (Microsoft Defender) ==="
Write-Output ("Host: {0}" -f $env:COMPUTERNAME)

$mp = $null
try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { Write-Output "[!] Defender cmdlets unavailable (Defender disabled/removed, or a third-party AV is managing this machine)." }
if ($mp) {
    Write-Output ("  Real-time protection : {0}" -f $mp.RealTimeProtectionEnabled)
    Write-Output ("  Antivirus enabled    : {0}" -f $mp.AntivirusEnabled)
    Write-Output ("  Engine / Signatures  : {0} / {1} (age {2}d)" -f $mp.AMEngineVersion, $mp.AntivirusSignatureVersion, $mp.AntivirusSignatureAge)
    Write-Output ("  Last quick scan      : {0}" -f $mp.QuickScanEndTime)
    Write-Output ("  Last full scan       : {0}" -f $mp.FullScanEndTime)
    if (-not $mp.RealTimeProtectionEnabled) { Write-Output "  [!] Real-time protection is OFF." }
    if ($mp.AntivirusSignatureAge -gt 7) { Write-Output "  [!] Signatures older than 7 days." }
    if ($mp.AMRunningMode -and $mp.AMRunningMode -ne 'Normal') { Write-Output ("  Running mode: {0} (a third-party AV is likely primary)." -f $mp.AMRunningMode) }
}

Write-Output "`n=== Threat History ==="
try {
    $threats = @(Get-MpThreatDetection -ErrorAction Stop | Sort-Object InitialDetectionTime -Descending)
    if ($threats.Count -gt 0) {
        $threats | Select-Object -First 10 | ForEach-Object {
            $t = $_
            $name = "$($t.ThreatID)"
            try { $tn = (Get-MpThreat -ThreatID $t.ThreatID -ErrorAction SilentlyContinue).ThreatName; if ($tn) { $name = $tn } } catch {}
            Write-Output ("  [!] {0:yyyy-MM-dd HH:mm}  {1}  (action: {2})" -f $t.InitialDetectionTime, $name, $t.CleaningActionID)
        }
    } else { Write-Output "  No threats recorded." }
} catch { Write-Output "  Threat history unavailable." }

if ($Update) {
    Write-Output "`n=== Updating signatures ==="
    try { Update-MpSignature -ErrorAction Stop; Write-Output "  OK - signatures updated." } catch { Write-Output ("  [!] Update failed: {0}" -f $_.Exception.Message) }
}

if ($Force) {
    $type = if ($Full) { 'FullScan' } else { 'QuickScan' }
    Write-Output ("`n=== Starting {0} ===" -f $type)
    try {
        Start-MpScan -ScanType $type -ErrorAction Stop
        Write-Output "  Scan complete."
        $after = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddMinutes(-30) })
        if ($after.Count -gt 0) { Write-Output ("  [!] {0} detection(s) during/just before this scan - see threat history above." -f $after.Count) }
        else { Write-Output "  No new detections." }
    } catch { Write-Output ("  [!] Scan failed: {0}" -f $_.Exception.Message) }
} else {
    Write-Output "`nReport only. Add -Force to run a scan (-Full for full), -Update to refresh signatures first."
}
