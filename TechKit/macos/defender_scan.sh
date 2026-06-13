#!/bin/bash
# SYNOPSIS: Antivirus status + scan. Uses Microsoft Defender (mdatp) if installed; otherwise
# reports the built-in macOS protections (XProtect/MRT/Gatekeeper). Reports by default;
# --force runs a scan. USAGE: bash defender_scan.sh [--force] [--full] [--update]
FORCE=0; FULL=0; UPDATE=0
for a in "$@"; do case "$a" in --force) FORCE=1;; --full) FULL=1;; --update) UPDATE=1;; esac; done

echo "=== Antivirus (macOS) ==="
echo "Host: $(hostname -s)"

MDATP=$(command -v mdatp 2>/dev/null)
if [ -n "$MDATP" ]; then
  echo "Engine: Microsoft Defender for Endpoint"
  echo ""
  echo "=== Health ==="
  echo "  healthy             : $(mdatp health --field healthy 2>/dev/null)"
  echo "  real-time protection: $(mdatp health --field real_time_protection_enabled 2>/dev/null)"
  echo "  definitions         : $(mdatp health --field definitions_status 2>/dev/null)"
  echo "  defs version        : $(mdatp health --field definitions_version 2>/dev/null)"

  echo ""
  echo "=== Threat History ==="
  TH=$(mdatp threat list 2>/dev/null)
  if [ -z "$TH" ] || echo "$TH" | grep -qi "No threats"; then echo "  No threats recorded."
  else echo "$TH" | sed 's/^/  [!] /' | head -20; fi

  [ "$UPDATE" -eq 1 ] && { echo ""; echo "=== Updating definitions ==="; mdatp definitions update 2>/dev/null | sed 's/^/  /'; }

  if [ "$FORCE" -eq 1 ]; then
    if [ "$FULL" -eq 1 ]; then echo ""; echo "=== Full scan (this can take a long time) ==="; mdatp scan full 2>/dev/null | sed 's/^/  /'
    else echo ""; echo "=== Quick scan ==="; mdatp scan quick 2>/dev/null | sed 's/^/  /'; fi
  else
    echo ""; echo "Report only. Add --force to scan (--full for full), --update to refresh definitions."
  fi
else
  echo "Engine: no Microsoft Defender (mdatp) found - reporting built-in macOS protections."
  echo ""
  echo "=== Built-in Protections ==="
  echo "  Gatekeeper : $(spctl --status 2>/dev/null)"
  echo "  SIP        : $(csrutil status 2>/dev/null | sed 's/.*: //')"
  XP="/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist"
  [ -f "$XP" ] && echo "  XProtect   : $(defaults read "$XP" CFBundleShortVersionString 2>/dev/null)"
  XPR="/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/Info.plist"
  [ -f "$XPR" ] && echo "  XProtect Remediator: $(defaults read "$XPR" CFBundleShortVersionString 2>/dev/null)"
  MRT="/System/Library/CoreServices/MRT.app/Contents/Info.plist"
  [ -f "$MRT" ] && echo "  MRT        : $(defaults read "$MRT" CFBundleShortVersionString 2>/dev/null)"
  echo ""
  echo "  [i] macOS has no built-in on-demand scanner. For an active scan install Defender (mdatp)"
  echo "      or a reputable on-demand tool. XProtect runs automatically in the background."
  echo ""
  echo "=== Recently Quarantined Downloads ==="
  sqlite3 "$HOME/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2" \
    "SELECT datetime(LSQuarantineTimeStamp+978307200,'unixepoch'), LSQuarantineAgentName, LSQuarantineDataURLString FROM LSQuarantineEvent ORDER BY LSQuarantineTimeStamp DESC LIMIT 8;" 2>/dev/null | sed 's/^/  /' \
    || echo "  (quarantine database unavailable)"
fi
