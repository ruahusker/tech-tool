#!/bin/bash
# SYNOPSIS: Reset OneDrive on macOS to fix stuck/failed sync. Re-syncs from cloud; does NOT delete files.
# DRY-RUN BY DEFAULT. No sudo needed (per-user).
# USAGE: bash reset_onedrive.sh           (preview)
#        bash reset_onedrive.sh --force   (apply)

FORCE=0; [ "$1" = "--force" ] && FORCE=1
APP="/Applications/OneDrive.app"
if [ ! -d "$APP" ]; then echo "[!] OneDrive not found in /Applications. Is it installed?"; exit 1; fi

# OneDrive ships a reset command inside the bundle (name varies by build).
RESET=""
for c in "$APP/Contents/Resources/ResetOneDriveApp.command" "$APP/Contents/Resources/ResetOneDriveAppStandalone.command"; do
  [ -f "$c" ] && RESET="$c" && break
done

MODE="DRY RUN (add --force to apply)"; [ "$FORCE" -eq 1 ] && MODE="EXECUTE"
echo "=== Reset OneDrive (macOS) ==="
echo "Mode: $MODE"
echo "Your files are NOT deleted — OneDrive re-syncs them after the reset."
echo ""

if [ "$FORCE" -eq 1 ]; then
  echo "  Quitting OneDrive..."
  osascript -e 'quit app "OneDrive"' 2>/dev/null; sleep 2; pkill -f OneDrive 2>/dev/null; sleep 1
  if [ -n "$RESET" ]; then
    echo "  Running reset command: $(basename "$RESET")"
    /bin/bash "$RESET" >/dev/null 2>&1
  else
    echo "  (no bundled reset command found; clearing OneDrive caches instead)"
    rm -rf "$HOME/Library/Caches/com.microsoft.OneDrive" "$HOME/Library/Caches/OneDrive" 2>/dev/null
    rm -rf "$HOME/Library/Application Support/OneDrive/settings" 2>/dev/null
  fi
  sleep 2
  echo "  Relaunching OneDrive..."
  open "$APP"
  echo ""
  echo "Done. OneDrive will reconnect and re-sync (may churn for a few minutes)."
else
  echo "  WOULD quit OneDrive, run its reset, then relaunch."
  [ -n "$RESET" ] && echo "  Reset command found: $RESET" || echo "  (would clear OneDrive caches — no bundled reset command on this build)"
  echo ""
  echo "Dry run complete. Re-run with --force to apply."
fi
