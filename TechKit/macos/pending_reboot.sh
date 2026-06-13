#!/bin/bash
# SYNOPSIS: Uptime and pending-update/restart status. Read-only.
# macOS has no Windows-style "pending reboot" flag, but long uptime + pending OS updates are
# the equivalent triage signals. USAGE: bash pending_reboot.sh
# NOTE: the pending-updates check contacts Apple and can take 10-30s.

echo "=== Uptime & Pending Restart (macOS) ==="
echo "Host: $(hostname -s)"

BOOT=$(sysctl -n kern.boottime 2>/dev/null | sed -E 's/.*sec = ([0-9]+),.*/\1/')
NOW=$(date +%s)
if [ -n "$BOOT" ]; then
  SECS=$((NOW - BOOT))
  DAYS=$((SECS/86400)); HRS=$(((SECS%86400)/3600)); MIN=$(((SECS%3600)/60))
  echo "  Last boot : $(date -r "$BOOT" 2>/dev/null)"
  echo "  Uptime    : ${DAYS}d ${HRS}h ${MIN}m"
  [ "$DAYS" -gt 14 ] && echo "  [!] Up for ${DAYS} days - a restart may clear lingering issues."
else
  echo "  Uptime: $(uptime)"
fi

echo ""
echo "=== Reboot / Shutdown History (last 5) ==="
last reboot 2>/dev/null | head -5 | sed 's/^/  /'

echo ""
echo "=== Pending macOS Updates (contacting Apple, may take a moment) ==="
UPD=$(softwareupdate --list 2>&1)
if echo "$UPD" | grep -qi "restart"; then
  echo "  [!] Update(s) requiring RESTART are pending:"
  echo "$UPD" | grep -iE "\*|restart|Label:" | sed 's/^/    /'
elif echo "$UPD" | grep -qi "No new software"; then
  echo "  No pending updates."
else
  echo "$UPD" | grep -iE "\*|Label:|Title:" | sed 's/^/  /' | head -10
fi

echo ""
echo "=== Staged Installer ==="
if ls -d /macOS\ Install*.app >/dev/null 2>&1 || ls -d /Applications/Install\ macOS*.app >/dev/null 2>&1; then
  echo "  [!] A staged macOS installer is present - a restart will apply it."
else
  echo "  No staged full-installer detected."
fi
echo "  [i] macOS applies most updates on restart; if an update 'won't finish', a restart is usually the fix."
