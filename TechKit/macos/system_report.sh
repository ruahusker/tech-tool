#!/bin/bash
# SYNOPSIS: One-page system overview: model, serial, OS, uptime, memory, storage summary.
# Read-only. First script to run on any unknown Mac. No sudo required.
# USAGE: bash system_report.sh

echo "=== IDENTITY ==="
HW=$(system_profiler SPHardwareDataType 2>/dev/null)
echo "$HW" | grep -E "Model Name|Model Identifier|Chip|Processor Name|Total Number of Cores|Memory|Serial Number" | sed 's/^ */  /'
echo "  Hostname      : $(scutil --get ComputerName 2>/dev/null) ($(hostname))"

echo ""
echo "=== OPERATING SYSTEM ==="
echo "  $(sw_vers -productName) $(sw_vers -productVersion) (build $(sw_vers -buildVersion))"
echo "  Kernel        : $(uname -mr)"
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    if /usr/bin/pgrep -q oahd 2>/dev/null; then echo "  Rosetta 2     : installed"; else echo "  Rosetta 2     : not installed"; fi
fi

echo ""
echo "=== UPTIME ==="
echo "  $(uptime | sed 's/^ *//')"
BOOTSEC=$(sysctl -n kern.boottime | awk -F'sec = ' '{print $2}' | awk -F',' '{print $1}')
if [ -n "$BOOTSEC" ]; then
    DAYS=$(( ( $(date +%s) - BOOTSEC ) / 86400 ))
    [ "$DAYS" -ge 14 ] && echo "  [!] Uptime over 14 days - a reboot often clears odd behavior."
fi

echo ""
echo "=== MEMORY ==="
TOTAL_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
echo "  Physical      : ${TOTAL_GB} GB"
echo "  Swap          : $(sysctl -n vm.swapusage | sed 's/  */ /g')"
PRESSURE=$(memory_pressure -Q 2>/dev/null | grep "System-wide memory free percentage" | grep -o '[0-9]*')
if [ -n "$PRESSURE" ]; then
    echo "  Free pressure : ${PRESSURE}% free"
    [ "$PRESSURE" -lt 15 ] && echo "  [!] Memory pressure high - see top_processes.sh"
fi

echo ""
echo "=== STORAGE SUMMARY ==="
df -h / /System/Volumes/Data 2>/dev/null | sed 's/^/  /' | awk '!seen[$0]++'
AVAIL_PCT=$(df /System/Volumes/Data 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
[ -n "$AVAIL_PCT" ] && [ "$AVAIL_PCT" -gt 90 ] && echo "  [!] Data volume over 90% used - see find_large_files.sh / clear_caches.sh"

echo ""
echo "=== POWER / BATTERY (if laptop) ==="
pmset -g batt 2>/dev/null | sed 's/^/  /'

echo ""
echo "=== LAST BOOT / SHUTDOWN HISTORY ==="
last reboot shutdown 2>/dev/null | head -6 | sed 's/^/  /'
