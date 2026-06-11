#!/bin/bash
# SYNOPSIS: MacBook battery health: cycle count, condition, capacity vs design, charger info.
# Read-only. Skips cleanly on desktops.
# USAGE: bash battery_health.sh

if ! pmset -g batt 2>/dev/null | grep -q "InternalBattery"; then
    echo "No internal battery - this appears to be a desktop Mac. Nothing to do."
    exit 0
fi

echo "=== LIVE STATUS ==="
pmset -g batt | sed 's/^/  /'

echo ""
echo "=== HEALTH (system_profiler) ==="
system_profiler SPPowerDataType 2>/dev/null | grep -E "Cycle Count|Condition|Maximum Capacity|Full Charge Capacity|Serial Number" | sed 's/^ */  /'

echo ""
echo "=== RAW CAPACITY (ioreg) ==="
IOREG=$(ioreg -rn AppleSmartBattery 2>/dev/null)
DESIGN=$(echo "$IOREG" | awk -F'= ' '/"DesignCapacity"/{print $2; exit}')
MAXCAP=$(echo "$IOREG" | awk -F'= ' '/"AppleRawMaxCapacity"/{print $2; exit}')
[ -z "$MAXCAP" ] && MAXCAP=$(echo "$IOREG" | awk -F'= ' '/"MaxCapacity"/{print $2; exit}')
CYCLES=$(echo "$IOREG" | awk -F'= ' '/"CycleCount"/{print $2; exit}')
if [ -n "$DESIGN" ] && [ -n "$MAXCAP" ] && [ "$DESIGN" -gt 0 ] 2>/dev/null; then
    PCT=$(( MAXCAP * 100 / DESIGN ))
    echo "  Design capacity : $DESIGN mAh"
    echo "  Current max     : $MAXCAP mAh"
    echo "  Health          : ${PCT}% of design"
    echo "  Cycle count     : $CYCLES"
    if [ "$PCT" -lt 80 ]; then echo "  [!] Below 80% - Apple's service threshold. Recommend battery service."; fi
else
    echo "  (could not read raw capacity values)"
fi

echo ""
echo "=== CHARGER ==="
pmset -g ac 2>/dev/null | sed 's/^/  /'
system_profiler SPPowerDataType 2>/dev/null | sed -n '/AC Charger Information/,/^$/p' | grep -E "Wattage|Connected|Charging|Name" | sed 's/^ */  /'

echo ""
echo "=== RECENT BATTERY DRAIN EVENTS ==="
pmset -g log 2>/dev/null | grep -E "Sleep.*Maintenance|Low Power|Shutdown" | tail -5 | cut -c1-140 | sed 's/^/  /'
echo ""
echo "Hint: 'Service Recommended' condition or health <80% with high cycles = battery, not the customer's imagination."
