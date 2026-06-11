<#
.SYNOPSIS
    Targeted connectivity test to a host: DNS, ping, TCP port, optional traceroute.
.DESCRIPTION
    Read-only. Use when a specific server/service is unreachable ("can't reach the file
    server", "app can't connect"). Pass the port the application actually uses.
.PARAMETER Target
    Hostname or IP to test (required).
.PARAMETER Port
    Optional TCP port to test (e.g. 443, 445 for SMB, 3389 for RDP).
.PARAMETER TraceRoute
    Include a traceroute (slower).
.EXAMPLE
    .\Test-Connectivity.ps1 -Target fileserver01 -Port 445
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Target,
    [int]$Port,
    [switch]$TraceRoute
)

Write-Output "=== DNS RESOLUTION: $Target ==="
try {
    $dns = Resolve-DnsName $Target -ErrorAction Stop
    $ips = ($dns | Where-Object Type -in 'A','AAAA').IPAddress
    Write-Output "  Resolves to: $($ips -join ', ')"
} catch {
    if ($Target -match '^\d{1,3}(\.\d{1,3}){3}$') { Write-Output "  (IP literal, skipping DNS)" }
    else { Write-Output "  [!] DNS FAILED: $($_.Exception.Message)"; Write-Output "  Try by IP if known; if IP works, problem is DNS." }
}

Write-Output "`n=== PING ==="
$ping = Test-Connection $Target -Count 4 -ErrorAction SilentlyContinue
if ($ping) {
    $times = $ping | ForEach-Object { if ($_.PSObject.Properties['ResponseTime']) { $_.ResponseTime } else { $_.Latency } }
    $avg = [math]::Round(($times | Measure-Object -Average).Average, 1)
    Write-Output "  OK - $($ping.Count)/4 replies, avg ${avg}ms"
    if ($avg -gt 150) { Write-Output "  [!] High latency for a LAN target (fine for internet/VPN)." }
} else {
    Write-Output "  No ping reply (note: many hosts/firewalls block ICMP - not conclusive alone)."
}

if ($Port) {
    Write-Output "`n=== TCP PORT $Port ==="
    $tcp = New-Object Net.Sockets.TcpClient
    try {
        $async = $tcp.BeginConnect($Target, $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne(5000) -and $tcp.Connected) {
            Write-Output "  OPEN - service is reachable on port $Port."
        } else {
            Write-Output "  [!] CLOSED/FILTERED - no TCP connection within 5s."
            Write-Output "  If ping works but the port fails: service down or firewall blocking that port."
        }
    } catch { Write-Output "  [!] FAILED: $($_.Exception.Message)" } finally { $tcp.Close() }
}

if ($TraceRoute) {
    Write-Output "`n=== TRACEROUTE ==="
    & tracert -d -h 20 -w 1000 $Target 2>&1 | ForEach-Object { Write-Output "  $_" }
}

Write-Output "`nCommon ports: 80/443 web, 445 SMB, 3389 RDP, 22 SSH, 25/587 SMTP, 389/636 LDAP, 1433 SQL, 9100 printing"
