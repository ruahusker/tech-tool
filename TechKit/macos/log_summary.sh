#!/bin/bash
# SYNOPSIS: Recent errors/faults from unified logging + crash reports + panic check.
# Read-only. The "what has been going wrong on this Mac" script.
# USAGE: bash log_summary.sh [hours]   (default 4; unified log queries get slow beyond ~24h)

HOURS=${1:-4}

echo "=== CRASH / HANG REPORTS (last 7 days) ==="
FOUND=0
for DIR in "$HOME/Library/Logs/DiagnosticReports" "/Library/Logs/DiagnosticReports"; do
    [ -d "$DIR" ] || continue
    REPORTS=$(find "$DIR" -maxdepth 1 \( -name "*.ips" -o -name "*.crash" -o -name "*.hang" -o -name "*.panic" \) -mtime -7 2>/dev/null)
    if [ -n "$REPORTS" ]; then
        FOUND=1
        echo "  [$DIR]"
        echo "$REPORTS" | while read -r R; do
            BASE=$(basename "$R")
            echo "    $BASE"
        done | sort | head -25
    fi
done
[ "$FOUND" -eq 0 ] && echo "  None in the last 7 days. Good sign."
PANICS=$(find /Library/Logs/DiagnosticReports "$HOME/Library/Logs/DiagnosticReports" -name "*.panic" -mtime -30 2>/dev/null | wc -l | tr -d ' ')
[ "$PANICS" != "0" ] && echo "  [!] $PANICS kernel panic(s) in last 30 days - suspect hardware, kexts, or overheating."

echo ""
echo "=== CRASH FREQUENCY BY APP (7 days) ==="
find "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports -maxdepth 1 -name "*.ips" -mtime -7 2>/dev/null \
    | sed 's#.*/##; s/[-_][0-9].*//' | sort | uniq -c | sort -rn | head -10 | sed 's/^/  /'

echo ""
echo "=== UNIFIED LOG: ERRORS+FAULTS (last ${HOURS}h, top sources) ==="
echo "  (querying unified log - takes a moment...)"
log show --last "${HOURS}h" --predicate 'messageType >= 16' --style compact 2>/dev/null \
    | awk '{print $4}' | sed 's/\[.*//' | sort | uniq -c | sort -rn | head -15 | sed 's/^/  /'

echo ""
echo "=== UNIFIED LOG: MOST RECENT FAULTS ==="
log show --last "${HOURS}h" --predicate 'messageType == 17' --style compact 2>/dev/null | tail -15 | cut -c1-160 | sed 's/^/  /'

echo ""
echo "=== WATCHDOG / FORCED REBOOTS ==="
last reboot 2>/dev/null | head -5 | sed 's/^/  /'
log show --last 7d --predicate 'eventMessage CONTAINS "Previous shutdown cause"' --style compact 2>/dev/null | tail -5 | sed 's/^/  /'
echo "  (shutdown cause 5=normal, -3/-40/-60s=power/thermal issues, -20=watchdog)"

echo ""
echo "Hints: open a specific .ips report and look at 'Termination Reason' + the crashed thread's top frames."
echo "Deep dive one app: log show --last 1h --predicate 'process == \"AppName\"'"
