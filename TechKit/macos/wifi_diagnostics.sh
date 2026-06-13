#!/bin/bash
# SYNOPSIS: Wi-Fi diagnostics: current link (SSID, signal/RSSI, channel, rate, security),
# radio/driver info, and saved networks. Read-only. sudo gives the richest detail (wdutil).
# USAGE: bash wifi_diagnostics.sh   (or: sudo bash wifi_diagnostics.sh)

echo "=== Wi-Fi Diagnostics (macOS) ==="
echo "Host: $(hostname -s)"

WIFI_IF=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi|AirPort/{getline; print $2; exit}')
echo "Wi-Fi interface: ${WIFI_IF:-not found}"
if [ -z "$WIFI_IF" ]; then echo "[!] No Wi-Fi hardware port found."; exit 0; fi

PWR=$(networksetup -getairportpower "$WIFI_IF" 2>/dev/null | sed 's/.*: //')
echo "Radio power: ${PWR:-unknown}"
CUR=$(networksetup -getairportnetwork "$WIFI_IF" 2>/dev/null | sed 's/.*Network: //')
echo "Connected SSID: ${CUR:-not associated}"

echo ""
echo "=== Link Quality ==="
if [ "$(id -u)" -eq 0 ]; then
  wdutil info 2>/dev/null | grep -iE "SSID|BSSID|RSSI|Noise|Tx Rate|Channel|PHY Mode|Security|MCS" | sed 's/^/  /'
else
  echo "  (run with sudo for live RSSI/noise/Tx-rate via wdutil)"
fi
system_profiler SPAirPortDataType 2>/dev/null | awk '/Current Network Information/{f=1} f{print} /Other Local Wi-Fi Networks/{f=0}' \
  | grep -iE "PHY Mode|Channel|Signal|Noise|Transmit Rate|Security|MCS" | sed 's/^/  /' | head -20

RSSI=$( { [ "$(id -u)" -eq 0 ] && wdutil info 2>/dev/null | grep -i RSSI; system_profiler SPAirPortDataType 2>/dev/null | grep -i "Signal / Noise"; } | grep -oE '\-[0-9]+' | head -1)
if [ -n "$RSSI" ]; then
  echo "  RSSI: ${RSSI} dBm"
  if [ "$RSSI" -lt -75 ] 2>/dev/null; then echo "  [!] Weak signal (under -75 dBm) - move closer to the AP or reduce interference."; fi
fi

echo ""
echo "=== Radio / Driver ==="
system_profiler SPAirPortDataType 2>/dev/null | grep -iE "Card Type|Firmware Version|Supported PHY Modes|Country Code" | sed 's/^/  /' | head -10

echo ""
echo "=== Saved Networks (preferred) ==="
networksetup -listpreferredwirelessnetworks "$WIFI_IF" 2>/dev/null | grep -v "Preferred networks" | sed 's/^[[:space:]]*/  - /' | head -30

echo ""
echo "[i] For a continuous capture use: sudo wdutil info  (or hold Option and click the Wi-Fi menu bar icon)."
