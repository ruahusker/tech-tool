#!/bin/bash
# SYNOPSIS: Kernel panics, app crashes, and recent diagnostic reports. Read-only.
# USAGE: bash crash_report.sh [days]   (default 14)
DAYS="${1:-14}"

echo "=== Crash & Panic Report (macOS) ==="
echo "Host: $(hostname -s)  |  Looking back: ${DAYS} days"

DIRS=("/Library/Logs/DiagnosticReports" "$HOME/Library/Logs/DiagnosticReports")

echo ""
echo "=== Kernel Panics ==="
PANIC=0
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || continue
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    PANIC=1
    echo "  [!] $(basename "$f")  ($(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null))"
    grep -m1 -iE "panic\(|Panic Reason|bug_type" "$f" 2>/dev/null | sed 's/^/        /' | cut -c1-160
  done < <(find "$d" \( -name "*.panic" -o -iname "Kernel*.ips" \) -mtime -"$DAYS" 2>/dev/null)
done
[ "$PANIC" -eq 0 ] && echo "  None in the last ${DAYS} days."

echo ""
echo "=== Recent App Crashes ==="
CR=0
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || continue
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    CR=1
    echo "  $(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null)  $(basename "$f")"
  done < <(find "$d" \( -name "*.crash" -o -name "*.ips" \) -mtime -"$DAYS" 2>/dev/null | grep -viE "Kernel|JetsamEvent" | head -20)
done
[ "$CR" -eq 0 ] && echo "  None in the last ${DAYS} days."

echo ""
echo "=== Top Crashing Apps ==="
TOP=$({ for d in "${DIRS[@]}"; do [ -d "$d" ] && find "$d" \( -name "*.crash" -o -name "*.ips" \) -mtime -"$DAYS" 2>/dev/null; done; } \
  | grep -viE "Kernel|JetsamEvent" | while IFS= read -r f; do basename "$f"; done | sed -E 's/[-_][0-9].*//' | sort | uniq -c | sort -rn | head -8 | sed 's/^/  /')
[ -n "$TOP" ] && echo "$TOP" || echo "  (none)"

echo ""
echo "=== Memory-Pressure Kills (Jetsam) ==="
JCOUNT=$({ for d in "${DIRS[@]}"; do [ -d "$d" ] && find "$d" -name "JetsamEvent*.ips" -mtime -"$DAYS" 2>/dev/null; done; } | wc -l | tr -d ' ')
echo "  ${JCOUNT:-0} app(s) killed by the OS for low memory in the last ${DAYS} days (these are NOT crashes)."
[ "${JCOUNT:-0}" -gt 10 ] && echo "  [!] Frequent memory-pressure kills - check RAM / Resource Usage; apps may be quitting on their own."

echo ""
echo "=== Previous Shutdown Causes (system log) ==="
SC=$(log show --predicate 'eventMessage CONTAINS "previous shutdown cause"' --last "${DAYS}d" --style compact 2>/dev/null | grep -i "shutdown cause:" | tail -5)
if [ -n "$SC" ]; then echo "$SC" | sed 's/^/  /'; else echo "  (no shutdown-cause records in window)"; fi
echo "  [i] cause 5 = normal, -3 = clean reboot; negative codes like -60/-71/-100s often = power/thermal/hardware."

echo ""
echo "Tip: open a .ips/.panic in Console.app, or run 'sudo spindump' to capture a current hang."
