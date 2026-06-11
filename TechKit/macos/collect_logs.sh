#!/bin/bash
# SYNOPSIS: Collect logs + crash reports into a tar.gz (default: USB TechKit/collections) for offline analysis.
# Read-only with respect to the machine. More complete with sudo (system log archive).
# USAGE: bash collect_logs.sh [hours_of_unified_log]   (default 4)

HOURS=${1:-4}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DEFAULT_OUT="$SCRIPT_DIR/../collections"
STAMP=$(date +%Y%m%d-%H%M%S)
HOST=$(hostname -s)
DEST="${DEFAULT_OUT}/${HOST}-logs-${STAMP}"
mkdir -p "$DEST" || { echo "Cannot create $DEST"; exit 1; }

echo "Collecting to: $DEST"

echo "  - crash/hang/panic reports (last 14 days)"
mkdir -p "$DEST/DiagnosticReports-user" "$DEST/DiagnosticReports-system"
find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -type f -mtime -14 -exec cp {} "$DEST/DiagnosticReports-user/" \; 2>/dev/null
find "/Library/Logs/DiagnosticReports" -maxdepth 1 -type f -mtime -14 -exec cp {} "$DEST/DiagnosticReports-system/" \; 2>/dev/null

echo "  - unified log (last ${HOURS}h, errors and faults)"
log show --last "${HOURS}h" --predicate 'messageType >= 16' --style syslog 2>/dev/null > "$DEST/unified-errors-${HOURS}h.log"

echo "  - install.log + system.log snippets"
tail -2000 /var/log/install.log  > "$DEST/install.log.tail" 2>/dev/null
tail -2000 /var/log/system.log   > "$DEST/system.log.tail"  2>/dev/null

echo "  - wifi diagnostics"
tail -2000 /var/log/wifi.log > "$DEST/wifi.log.tail" 2>/dev/null

if [ "$(id -u)" -eq 0 ]; then
    echo "  - full unified log archive (sudo detected; this is the gold standard)"
    log collect --last "${HOURS}h" --output "$DEST/system_logs.logarchive" 2>/dev/null
else
    echo "  (run with sudo to also capture a .logarchive bundle viewable in Console.app)"
fi

cat > "$DEST/MANIFEST.txt" <<EOF
Log collection
Host    : $(hostname)
macOS   : $(sw_vers -productVersion) ($(sw_vers -buildVersion))
Taken   : $(date "+%Y-%m-%d %H:%M:%S")
By      : $(whoami) (euid $(id -u))
Window  : ${HOURS}h unified log, 14d crash reports
EOF

TARBALL="${DEST}.tar.gz"
tar -czf "$TARBALL" -C "$(dirname "$DEST")" "$(basename "$DEST")" 2>/dev/null && {
    echo ""
    echo "Done: $TARBALL ($(du -h "$TARBALL" | cut -f1))"
    echo "Folder kept too: $DEST"
} || echo "Done (tar failed, folder kept): $DEST"
