#!/bin/bash
# SYNOPSIS: Force a Jamf check-in / inventory / policy refresh so stuck policies and inventory recover.
# DRY-RUN BY DEFAULT. Needs sudo. The nuclear re-enroll (--reenroll) UNMANAGES the device — gated.
#
# Safe tier (default with --force): jamf policy (check-in), jamf recon (submit inventory),
# jamf manage (re-apply management framework/MDM), and flush stuck policy history so failed
# policies re-run. This fixes most "the policy never ran / inventory is stale" cases.
#
# USAGE:
#   bash reset_jamf.sh                    # preview
#   sudo bash reset_jamf.sh --force       # force check-in + inventory + policy refresh
#   sudo bash reset_jamf.sh --reenroll --force   # NUCLEAR: remove framework to re-enroll (unmanages!)

FORCE=0; REENROLL=0
for a in "$@"; do case "$a" in --force) FORCE=1;; --reenroll) REENROLL=1;; esac; done

JAMF=""
for p in /usr/local/bin/jamf /usr/local/jamf/bin/jamf; do [ -x "$p" ] && JAMF="$p" && break; done
if [ -z "$JAMF" ]; then echo "[!] Jamf binary not found — this Mac isn't managed by Jamf. Nothing to do."; exit 0; fi

STAMP="$(date +%Y%m%d-%H%M%S)"; SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGFILE="$SCRIPT_DIR/../collections/$(hostname -s)-jamf-reset-$STAMP.log"
MODE="DRY RUN (preview only; add --force to apply)"; [ "$FORCE" -eq 1 ] && MODE="EXECUTE"
log(){ echo "  $1"; if [ "$FORCE" -eq 1 ]; then mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null; echo "$(date '+%Y-%m-%d %H:%M:%S')  $1" >> "$LOGFILE" 2>/dev/null; fi; }
run(){ local desc="$1"; shift; if [ "$FORCE" -eq 1 ]; then "$@" >/dev/null 2>&1 && log "$desc — ok" || log "$desc — FAILED"; else echo "  WOULD $desc"; fi; }

echo "=== Jamf Check-in / Reset ==="
echo "Mode: $MODE  |  Host: $(hostname -s)  |  jamf: $JAMF"
[ "$FORCE" -eq 1 ] && [ "$(id -u)" -ne 0 ] && { echo "[!] --force needs sudo. Aborting."; exit 1; }
echo ""

echo "=== Current management status ==="
"$JAMF" checkJSSConnection 2>/dev/null | sed 's/^/  /' | head -3
echo ""

echo "=== STEP: refresh management (safe) ==="
run "submit inventory (jamf recon)" "$JAMF" recon
run "re-apply management framework (jamf manage)" "$JAMF" manage
run "flush stuck policy history (jamf flushPolicyHistory)" "$JAMF" flushPolicyHistory
run "force check-in / run pending policies (jamf policy)" "$JAMF" policy

if [ "$REENROLL" -eq 1 ]; then
  echo ""
  echo "=== STEP: NUCLEAR re-enroll (removes the Jamf framework) ==="
  echo "  [!] This UNMANAGES the device. It must be re-enrolled (DEP/ADE auto, or user-initiated)."
  if [ "$FORCE" -eq 1 ]; then
    "$JAMF" removeFramework >/dev/null 2>&1 && log "removed Jamf framework — device is now unmanaged; re-enroll required" || log "removeFramework FAILED"
  else
    echo "  WOULD run 'jamf removeFramework' (device becomes unmanaged until re-enrolled)"
  fi
fi

echo ""
if [ "$FORCE" -eq 1 ]; then
  echo "Done. Action log: $LOGFILE"
  [ "$REENROLL" -eq 0 ] && echo "Policies/inventory refreshed. Check the Jamf console or run 'sudo jamf policy -verbose' to watch a policy run."
else
  echo "Dry run complete. Re-run with sudo and --force. Add --reenroll only when the device must be re-enrolled."
fi
