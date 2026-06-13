<#
.SYNOPSIS
    Wi-Fi diagnostics: connection quality (signal, channel, band, BSSID), radio/driver info,
    and saved network profiles. Read-only.
.DESCRIPTION
    For "Wi-Fi is slow/drops", "won't connect", "weak signal". Shows the live link (SSID,
    signal %, radio type, channel, receive/transmit rate), the wireless adapter driver, and
    every saved profile. -Report generates the full Windows WLAN report (HTML) to the
    collections folder. -ShowKey reveals the saved password for the current network (admin).
.PARAMETER Report
    Generate the detailed Windows WLAN report (HTML + connection/roaming history).
.PARAMETER ShowKey
    Reveal the stored key (password) for the connected network. Requires elevation.
#>
[CmdletBinding()]
param([switch]$Report,[switch]$ShowKey)

Write-Output "=== Wi-Fi Diagnostics ==="
Write-Output ("Host: {0}" -f $env:COMPUTERNAME)

$iface = & netsh wlan show interfaces 2>$null
if (-not $iface -or ($iface -match 'There is no wireless interface')) {
    Write-Output "[!] No wireless interface found (no Wi-Fi adapter, or WLAN AutoConfig service is off)."
    $wlansvc = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
    if ($wlansvc) { Write-Output ("    WLAN AutoConfig (WlanSvc): {0}" -f $wlansvc.Status) }
    return
}

Write-Output "`n=== Current Connection ==="
$iface | Where-Object { $_ -match 'Name|Description|State|SSID|BSSID|Radio type|Channel|Receive rate|Transmit rate|Signal|Authentication|Cipher|Band' -and $_ -notmatch 'Hosted network' } | ForEach-Object { Write-Output ("  {0}" -f $_.Trim()) }

$sigLine = @($iface | Where-Object { $_ -match '^\s*Signal' })
if ($sigLine.Count -gt 0) {
    $pct = ($sigLine[0] -replace '[^0-9]','')
    if ($pct) { $p = [int]$pct; if ($p -lt 40) { Write-Output ("  [!] Weak signal ({0}%) - move closer to the AP or check for interference." -f $p) } }
}

Write-Output "`n=== Radio / Driver ==="
& netsh wlan show drivers 2>$null | Where-Object { $_ -match 'Driver version|Date|Radio types supported|INF file|Vendor' } | ForEach-Object { Write-Output ("  {0}" -f $_.Trim()) }

Write-Output "`n=== Saved Profiles ==="
$profiles = & netsh wlan show profiles 2>$null | Where-Object { $_ -match 'All User Profile' } | ForEach-Object { ($_ -split ':',2)[1].Trim() }
if ($profiles) { $profiles | ForEach-Object { Write-Output ("  - {0}" -f $_) } }
else { Write-Output "  (none)" }

if ($ShowKey) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $curSsid = ((@($iface | Where-Object { $_ -match '^\s*SSID' -and $_ -notmatch 'BSSID' })[0]) -replace '.*:\s*','').Trim()
    if (-not $isAdmin) { Write-Output "`n[!] -ShowKey needs elevation." }
    elseif ($curSsid) {
        Write-Output ("`n=== Stored Key for '{0}' ===" -f $curSsid)
        & netsh wlan show profile name="$curSsid" key=clear 2>$null | Where-Object { $_ -match 'Key Content' } | ForEach-Object { Write-Output ("  {0}" -f $_.Trim()) }
    }
}

if ($Report) {
    $dest = Join-Path $PSScriptRoot "..\collections"
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
    Write-Output "`n=== Generating WLAN report ==="
    & netsh wlan show wlanreport 2>$null | Out-Null
    $src = Join-Path $env:ProgramData "Microsoft\Windows\WlanReport\wlan-report-latest.html"
    if (Test-Path $src) {
        $dst = Join-Path $dest ("{0}-wlanreport-{1}.html" -f $env:COMPUTERNAME, (Get-Date -Format yyyyMMdd-HHmmss))
        Copy-Item $src $dst -Force
        Write-Output ("  Saved: {0}" -f $dst)
    } else { Write-Output "  [!] Report not generated (needs elevation)." }
}
