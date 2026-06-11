#!/bin/bash
# SYNOPSIS: Layered network check: interfaces, gateway, DNS, internet, proxy, Wi-Fi, VPN.
# Read-only. Run for any "no internet" complaint; output shows which layer is broken.
# USAGE: bash network_diagnostics.sh

echo "=== ACTIVE INTERFACES ==="
for IF in $(ifconfig -lu); do
    case "$IF" in lo0|awdl*|llw*|bridge*|gif*|stf*|anpi*|ap1) continue;; esac
    IP=$(ipconfig getifaddr "$IF" 2>/dev/null)
    if [ -n "$IP" ]; then
        HW=$(networksetup -listallhardwareports 2>/dev/null | grep -B1 "Device: $IF" | head -1 | cut -d: -f2 | sed 's/^ *//')
        echo "  $IF (${HW:-?}): $IP"
    fi
done
echo "  VPN/tunnel interfaces up: $(ifconfig -lu | tr ' ' '\n' | grep -c '^utun')x utun"

echo ""
echo "=== LAYERED CONNECTIVITY TEST ==="
GW=$(route -n get default 2>/dev/null | awk '/gateway/{print $2}')
if [ -n "$GW" ]; then
    if ping -c 2 -t 3 "$GW" >/dev/null 2>&1; then echo "  1. Gateway ping ($GW)     : OK"
    else echo "  1. Gateway ping ($GW)     : FAIL [!] local network problem"; fi
else
    echo "  1. Default gateway         : NONE [!] no route - check Wi-Fi/cable/DHCP"
fi
if ping -c 2 -t 3 1.1.1.1 >/dev/null 2>&1; then echo "  2. Internet by IP (1.1.1.1): OK"
else echo "  2. Internet by IP (1.1.1.1): FAIL [!] upstream/firewall problem"; fi
if dscacheutil -q host -a name www.apple.com 2>/dev/null | grep -q ip_address; then echo "  3. DNS resolution          : OK"
else echo "  3. DNS resolution          : FAIL [!] DNS broken (internet by IP may still work)"; fi
HTTP=$(curl -s --max-time 5 http://captive.apple.com 2>/dev/null)
if echo "$HTTP" | grep -q "Success"; then echo "  4. HTTP reachability       : OK"
elif [ -n "$HTTP" ]; then echo "  4. HTTP reachability       : [!] unexpected reply - captive portal or proxy interception"
else echo "  4. HTTP reachability       : FAIL [!] port 80 blocked or no connectivity"; fi

echo ""
echo "=== DNS CONFIGURATION ==="
scutil --dns 2>/dev/null | grep "nameserver\[" | sort -u | sed 's/^ */  /'

echo ""
echo "=== PROXY ==="
scutil --proxy 2>/dev/null | grep -E "Enable|Proxy|Port" | grep -v "0$" | sed 's/^ */  /'
PROXY_ON=$(scutil --proxy 2>/dev/null | grep -E "(HTTP|HTTPS|SOCKS)Enable : 1")
[ -z "$PROXY_ON" ] && echo "  No proxy enabled."

echo ""
echo "=== WI-FI ==="
WIFI_IF=$(networksetup -listallhardwareports 2>/dev/null | grep -A1 "Wi-Fi" | awk '/Device/{print $2}')
if [ -n "$WIFI_IF" ]; then
    networksetup -getairportnetwork "$WIFI_IF" 2>/dev/null | sed 's/^/  /'
    # wdutil gives signal info but needs sudo; degrade gracefully
    if [ "$(id -u)" -eq 0 ]; then
        wdutil info 2>/dev/null | grep -E "SSID|RSSI|Noise|Tx Rate|Channel" | sed 's/^ */  /'
    else
        system_profiler SPAirPortDataType 2>/dev/null | grep -A8 "Current Network" | grep -E "PHY Mode|Channel|Signal|Transmit" | sed 's/^ */  /'
        echo "  (run with sudo for RSSI/noise detail via wdutil)"
    fi
else
    echo "  No Wi-Fi hardware port."
fi

echo ""
echo "Reset hints (manual): sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder   # DNS cache"
echo "Renew DHCP: sudo ipconfig set <if> DHCP. Wi-Fi off/on: networksetup -setairportpower <if> off/on"
