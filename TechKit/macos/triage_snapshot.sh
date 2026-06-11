#!/bin/bash
# SYNOPSIS: One-shot triage: run every read-only diagnostic, save all output to a timestamped
# folder on the USB (TechKit/collections). Run first when you don't yet know what's wrong.
# Read-only. ~2-4 minutes. USAGE: bash triage_snapshot.sh [out_dir]

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
OUT_BASE="${1:-$SCRIPT_DIR/../collections}"
STAMP=$(date +%Y%m%d-%H%M%S)
DEST="$OUT_BASE/$(hostname -s)-triage-$STAMP"
mkdir -p "$DEST" || { echo "Cannot create $DEST"; exit 1; }

echo "Triage snapshot -> $DEST"
echo ""

run_script() {  # name script [args...]
    NAME="$1"; shift
    SCRIPT="$1"; shift
    if [ -f "$SCRIPT_DIR/$SCRIPT" ]; then
        echo "  running $SCRIPT ..."
        bash "$SCRIPT_DIR/$SCRIPT" "$@" > "$DEST/$NAME.txt" 2>&1
    fi
}

run_script "system-report"   "system_report.sh"
run_script "disk-health"     "disk_health.sh"
run_script "top-processes"   "top_processes.sh"
run_script "startup-items"   "startup_items.sh"
run_script "network"         "network_diagnostics.sh"
run_script "log-summary"     "log_summary.sh" 4
run_script "update-status"   "update_status.sh"
run_script "security-status" "security_status.sh"
run_script "user-accounts"   "user_account_report.sh"
run_script "battery"         "battery_health.sh"

echo "  collecting raw extras ..."
ifconfig -a                       > "$DEST/raw-ifconfig.txt"   2>&1
netstat -rn                       > "$DEST/raw-routes.txt"     2>&1
ps aux                            > "$DEST/raw-ps.txt"         2>&1
system_profiler SPSoftwareDataType SPHardwareDataType SPStorageDataType SPDisplaysDataType \
                                  > "$DEST/raw-profiler.txt"   2>&1
ls -la /Applications              > "$DEST/raw-applications.txt" 2>&1
kextstat 2>/dev/null | grep -v com.apple > "$DEST/raw-thirdparty-kexts.txt"

cat > "$DEST/MANIFEST.txt" <<EOF
Triage snapshot
Host    : $(hostname)
macOS   : $(sw_vers -productVersion) ($(sw_vers -buildVersion))
Taken   : $(date "+%Y-%m-%d %H:%M:%S")
By      : $(whoami) (euid $(id -u))
Kit     : TechKit macos
EOF

TARBALL="$DEST.tar.gz"
tar -czf "$TARBALL" -C "$(dirname "$DEST")" "$(basename "$DEST")" 2>/dev/null && {
    echo ""
    echo "Snapshot complete: $DEST"
    echo "Tarball         : $TARBALL"
} || echo "Snapshot complete (tar failed, folder kept): $DEST"
