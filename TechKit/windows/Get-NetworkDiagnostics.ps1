<#
.SYNOPSIS
    Full network health check: adapters, IP config, gateway, DNS, internet, proxy, Wi-Fi.
.DESCRIPTION
    Read-only. Run for any "no internet" / "can't reach X" complaint. Tests each layer in
    order (link -> IP -> gateway -> DNS -> internet) so the output pinpoints where it breaks.
#>
[CmdletBinding()]
param()

Write-Output "=== ADAPTERS ==="
Get-NetAdapter | Sort-Object -Property Status -Descending | ForEach-Object {
    Write-Output ("  {0,-28} {1,-12} {2,-10} {3}" -f $_.Name, $_.Status, $_.LinkSpeed, $_.InterfaceDescription)
}

Write-Output "`n=== IP CONFIGURATION (active adapters) ==="
$active = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' }
foreach ($cfg in $active) {
    Write-Output "  [$($cfg.InterfaceAlias)]"
    $cfg.IPv4Address | ForEach-Object { Write-Output "    IPv4    : $($_.IPAddress)/$($_.PrefixLength)" }
    if ($cfg.IPv4DefaultGateway) { Write-Output "    Gateway : $($cfg.IPv4DefaultGateway.NextHop)" }
    Write-Output "    DNS     : $(($cfg.DNSServer | Where-Object AddressFamily -eq 2).ServerAddresses -join ', ')"
    $dhcp = (Get-NetIPInterface -InterfaceIndex $cfg.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).Dhcp
    Write-Output "    DHCP    : $dhcp"
    if (($cfg.IPv4Address.IPAddress | Select-Object -First 1) -like '169.254.*') {
        Write-Output "    [!] APIPA address - DHCP failed. Check cable/Wi-Fi, then the DHCP server."
    }
}

Write-Output "`n=== LAYERED CONNECTIVITY TEST ==="
$gw = ($active | Where-Object IPv4DefaultGateway | Select-Object -First 1).IPv4DefaultGateway.NextHop
if ($gw) {
    $gwOk = Test-Connection $gw -Count 2 -Quiet
    Write-Output ("  1. Gateway ping ({0})      : {1}" -f $gw, $(if($gwOk){"OK"}else{"FAIL [!] - local network problem"}))
} else { Write-Output "  1. Gateway: NONE FOUND [!] - no route off this machine"; $gwOk = $false }
$ipOk = Test-Connection 1.1.1.1 -Count 2 -Quiet
Write-Output ("  2. Internet by IP (1.1.1.1) : {0}" -f $(if($ipOk){"OK"}else{"FAIL [!] - upstream/firewall problem"}))
$dnsOk = $false
try { $null = Resolve-DnsName "www.microsoft.com" -ErrorAction Stop -QuickTimeout; $dnsOk = $true } catch {}
Write-Output ("  3. DNS resolution           : {0}" -f $(if($dnsOk){"OK"}else{"FAIL [!] - DNS broken (internet by IP may still work)"}))
if ($ipOk) {
    try {
        $http = Invoke-WebRequest -Uri "http://www.msftconnecttest.com/connecttest.txt" -UseBasicParsing -TimeoutSec 5
        $portal = if ($http.Content -eq "Microsoft Connect Test") { "OK" } else { "[!] Unexpected reply - possible captive portal/proxy interception" }
        Write-Output "  4. HTTP reachability        : $portal"
    } catch { Write-Output "  4. HTTP reachability        : FAIL [!] - port 80 blocked or proxy required" }
}

Write-Output "`n=== PROXY ==="
& netsh winhttp show proxy 2>$null | Where-Object { $_ -match '\S' } | ForEach-Object { Write-Output "  $_" }
$ieProxy = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
Write-Output ("  User proxy enabled: {0}  Server: {1}" -f [bool]$ieProxy.ProxyEnable, $ieProxy.ProxyServer)

Write-Output "`n=== WI-FI (if applicable) ==="
$wlan = & netsh wlan show interfaces 2>$null
if ($LASTEXITCODE -eq 0 -and $wlan -match "SSID") {
    $wlan | Where-Object { $_ -match "Name|State|SSID|Signal|Channel|Radio type|Receive rate|Authentication" } | ForEach-Object { Write-Output "  $($_.Trim())" }
    $sig = ($wlan | Select-String "Signal\s*:\s*(\d+)%").Matches
    if ($sig.Count -and [int]$sig[0].Groups[1].Value -lt 50) { Write-Output "  [!] Weak signal (<50%) - expect drops/slowness." }
} else { Write-Output "  No active Wi-Fi interface." }

Write-Output "`n=== DNS CACHE / RESET HINTS (manual, not run automatically) ==="
Write-Output "  ipconfig /flushdns ; ipconfig /release ; ipconfig /renew"
Write-Output "  netsh winsock reset ; netsh int ip reset   (then reboot)"
