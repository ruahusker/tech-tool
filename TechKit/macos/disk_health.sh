#!/bin/bash
# SYNOPSIS: Disk health: SMART status, space, APFS container, optional live verify.
# Read-only. Run for slowness, freezes, or suspected drive failure.
# USAGE: bash disk_health.sh [--verify]

echo "=== DISKS ==="
diskutil list internal physical 2>/dev/null | sed 's/^/  /'

echo ""
echo "=== SMART STATUS ==="
for DISK in $(diskutil list internal physical 2>/dev/null | grep -o '^/dev/disk[0-9]*'); do
    INFO=$(diskutil info "$DISK" 2>/dev/null)
    NAME=$(echo "$INFO" | grep "Device / Media Name" | cut -d: -f2 | sed 's/^ *//')
    SMART=$(echo "$INFO" | grep "SMART Status" | cut -d: -f2 | sed 's/^ *//')
    echo "  $DISK ($NAME): SMART = $SMART"
    if [ "$SMART" != "Verified" ] && [ "$SMART" != "Not Supported" ] && [ -n "$SMART" ]; then
        echo "  [!] SMART not 'Verified' - back up immediately and plan drive replacement."
    fi
done

echo ""
echo "=== SPACE ==="
df -h / /System/Volumes/Data 2>/dev/null | awk '!seen[$0]++' | sed 's/^/  /'
echo ""
echo "  APFS container usage:"
diskutil apfs list 2>/dev/null | grep -E "Capacity (Ceiling|In Use|Not Allocated)" | sed 's/^ */    /'

echo ""
echo "=== PURGEABLE / SNAPSHOT SPACE ==="
SNAPS=$(diskutil apfs listSnapshots /System/Volumes/Data 2>/dev/null | grep -c "Snapshot " )
echo "  Local APFS snapshots on Data volume: ${SNAPS:-0}"
if [ "${SNAPS:-0}" -gt 5 ]; then
    echo "  [!] Many local snapshots (often Time Machine) can hold space hostage."
    echo "      List: tmutil listlocalsnapshots /   Thin: sudo tmutil thinlocalsnapshots / 999999999999 4"
fi

if [ "$1" = "--verify" ]; then
    echo ""
    echo "=== LIVE VOLUME VERIFY (read-only check, a few minutes) ==="
    diskutil verifyVolume /System/Volumes/Data 2>&1 | sed 's/^/  /'
else
    echo ""
    echo "Run with --verify for a live filesystem check (read-only, takes a few minutes)."
fi

echo ""
echo "Hints: full repair needs Recovery Mode (Disk Utility First Aid). For I/O errors check log_summary.sh for 'disk' / 'apfs' errors."
