#!/bin/bash
# SYNOPSIS: CPU and memory hogs, memory pressure, swap, load. The "Mac is slow" script.
# Read-only. No sudo required.
# USAGE: bash top_processes.sh [top_n]

TOP_N=${1:-12}

echo "=== LOAD ==="
echo "  $(uptime | sed 's/^ *//')"
echo "  Logical CPUs: $(sysctl -n hw.ncpu)"

echo ""
echo "=== TOP BY CPU (live sample) ==="
# Second sample of top is the accurate one
top -l 2 -n "$TOP_N" -o cpu -stats pid,command,cpu,mem,state 2>/dev/null | awk '/^Processes:/{block++} block==2 && NR>0' | grep -A "$((TOP_N+2))" "^PID" | head -$((TOP_N+1)) | sed 's/^/  /'

echo ""
echo "=== TOP BY MEMORY ==="
ps axo rss,pcpu,pid,comm | sort -rn | head -"$TOP_N" | awk '{printf "  %8.0f MB  %5s%%  %s (pid %s)\n", $1/1024, $2, $4, $3}'

echo ""
echo "=== MEMORY PRESSURE ==="
PRESSURE=$(memory_pressure -Q 2>/dev/null | grep "System-wide memory free percentage" | grep -o '[0-9]*')
echo "  Free percentage : ${PRESSURE:-unknown}%"
echo "  Swap            : $(sysctl -n vm.swapusage | sed 's/  */ /g')"
vm_stat 2>/dev/null | grep -E "Pages free|Pageouts|Pages occupied by compressor" | sed 's/^/  /'
if [ -n "$PRESSURE" ] && [ "$PRESSURE" -lt 15 ]; then
    echo "  [!] High memory pressure. Check the memory list above; browsers with many tabs are the usual suspect."
fi

echo ""
echo "=== HUNG PROCESSES (state stuck/uninterruptible) ==="
HUNG=$(ps axo state,pid,comm | awk '$1 ~ /U/ {print "  "$0}')
if [ -n "$HUNG" ]; then echo "$HUNG"; echo "  [!] 'U' state = waiting on I/O - can indicate disk or network-mount trouble."
else echo "  None."; fi

echo ""
echo "=== THERMAL THROTTLING ==="
pmset -g therm 2>/dev/null | sed 's/^/  /'
echo "  (CPU_Speed_Limit < 100 means the machine is throttling - check vents/fans.)"
