#!/bin/bash
# SYNOPSIS: Reset macOS printing: clear stuck jobs and restart CUPS. DRY-RUN BY DEFAULT.
# --remove-printers also removes ALL configured printers (the full "Reset printing system").
# Needs sudo to restart CUPS / remove printers. Re-add the printer afterward.
# USAGE: bash reset_printing.sh            (preview)
#        sudo bash reset_printing.sh --force
#        sudo bash reset_printing.sh --force --remove-printers

FORCE=0; REMOVE=0
for a in "$@"; do case "$a" in --force) FORCE=1;; --remove-printers) REMOVE=1;; esac; done
MODE="DRY RUN (add --force to apply)"; [ "$FORCE" -eq 1 ] && MODE="EXECUTE"

echo "=== Reset Printing (macOS) ==="
echo "Mode: $MODE  |  Host: $(hostname -s)"
[ "$FORCE" -eq 1 ] && [ "$(id -u)" -ne 0 ] && echo "Note: not running with sudo - CUPS restart / printer removal will be skipped."
echo ""

echo "Current printers:"
lpstat -p 2>/dev/null | sed 's/^/  /' || echo "  (none)"
JOBS=$(lpstat -o 2>/dev/null | wc -l | tr -d ' ')
echo "Queued jobs: ${JOBS:-0}"
echo ""

step(){ local desc="$1"; shift; if [ "$FORCE" -eq 1 ]; then "$@" >/dev/null 2>&1 && echo "  OK  : $desc" || echo "  [!] : $desc (failed)"; else echo "  WOULD $desc"; fi; }

step "cancel all queued print jobs" cancel -a -x

if [ "$REMOVE" -eq 1 ]; then
  if [ "$FORCE" -eq 1 ] && [ "$(id -u)" -eq 0 ]; then
    for P in $(lpstat -p 2>/dev/null | awk '/^printer/{print $2}'); do
      lpadmin -x "$P" 2>/dev/null && echo "  OK  : removed printer $P"
    done
  else
    echo "  WOULD remove ALL configured printers (needs sudo + --force)"
  fi
fi

if [ "$(id -u)" -eq 0 ]; then
  step "restart CUPS (cupsd)" launchctl kickstart -k system/org.cups.cupsd
elif [ "$FORCE" -eq 0 ]; then
  echo "  WOULD restart CUPS (needs sudo)"
fi

echo ""
if [ "$FORCE" -eq 1 ]; then echo "Done. Re-add the printer if you used --remove-printers, then test a print."
else echo "Dry run complete. Re-run with sudo and --force. Add --remove-printers for a full reset."; fi
