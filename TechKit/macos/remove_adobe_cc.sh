#!/bin/bash
# SYNOPSIS: Deep uninstall of Adobe Creative Cloud + apps for macOS, including the daemons,
#           leftovers, and licensing a normal uninstall misses. Clears sign-in so it re-authenticates.
# DESTRUCTIVE - DRY-RUN BY DEFAULT. Needs sudo for /Library items, LaunchDaemons, and pkg receipts.
#
# SAFETY:
#   - Never touches your creative files (Documents/Pictures/Desktop) — only Adobe's own
#     app-support, prefs, caches, daemons, and licensing.
#   - Keeps the free Adobe Acrobat Reader by default (pass --remove-all to remove it too).
#
# USAGE:
#   bash remove_adobe_cc.sh                       # preview
#   sudo bash remove_adobe_cc.sh --force          # deep uninstall + clear sign-in
#   options: --remove-all (also Acrobat Reader)   --clean-hosts (remove Adobe license-block lines)

FORCE=0; RM_ALL=0; CLEAN_HOSTS=0
for a in "$@"; do case "$a" in
  --force) FORCE=1;; --remove-all) RM_ALL=1;; --clean-hosts) CLEAN_HOSTS=1;;
esac; done

CALLER="${SUDO_USER:-$(whoami)}"
HOME_DIR="$(eval echo ~"$CALLER")"
STAMP="$(date +%Y%m%d-%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGFILE="$SCRIPT_DIR/../collections/$(hostname -s)-adobe-removal-$STAMP.log"
MODE="DRY RUN (preview only; add --force to apply)"; [ "$FORCE" -eq 1 ] && MODE="EXECUTE"

log() { echo "  $1"; if [ "$FORCE" -eq 1 ]; then mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null; echo "$(date '+%Y-%m-%d %H:%M:%S')  $1" >> "$LOGFILE" 2>/dev/null; fi; }
rm_path() {
  local p="$1" label="${2:-$1}"
  [ -e "$p" ] || return 0
  if [ "$FORCE" -eq 1 ]; then rm -rf "$p" 2>/dev/null && log "removed $label" || log "FAILED to remove $label"
  else echo "  WOULD remove $label"; fi
}
# Is this com.adobe.* item the free Acrobat Reader? (kept unless --remove-all)
is_reader() { echo "$1" | tr 'A-Z' 'a-z' | grep -q "reader\|acrobat"; }

echo "=== Adobe Creative Cloud Deep Removal (macOS) ==="
echo "Mode: $MODE  |  User: $CALLER"
[ "$(id -u)" -ne 0 ] && echo "Note: not running with sudo — /Library items, LaunchDaemons, and pkg receipts will be skipped (re-run with sudo for a complete clean)."
echo ""

# ---------- inventory ----------
echo "=== Installed Adobe apps ==="
ls -d /Applications/Adobe* 2>/dev/null | while read -r app; do
  v=$(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
  echo "  $(basename "$app")  ${v:-}"
done
[ "$RM_ALL" -eq 0 ] && echo "  (keeping Adobe Acrobat Reader — pass --remove-all to remove it too)"
echo ""

# ---------- quit processes ----------
echo "=== STEP: quit Adobe processes ==="
for proc in "Creative Cloud" "Core Sync" "Adobe Desktop Service" "AdobeIPCBroker" "CCXProcess" "CCLibrary" \
            "Adobe Crash Processor" "Adobe Genuine Service" "AdobeGCClient" "Adobe CEF Helper" \
            "Photoshop" "Illustrator" "Adobe Premiere Pro" "After Effects" "InDesign" "Lightroom" "Adobe Bridge"; do
  if pgrep -f "$proc" >/dev/null 2>&1; then
    if [ "$RM_ALL" -eq 0 ] && echo "$proc" | grep -qi acrobat; then continue; fi
    if [ "$FORCE" -eq 1 ]; then osascript -e "quit app \"$proc\"" 2>/dev/null; sleep 1; pkill -f "$proc" 2>/dev/null; log "quit $proc"
    else echo "  WOULD quit $proc"; fi
  fi
done
echo ""

# ---------- stop + remove launchd daemons/agents ----------
echo "=== STEP: stop + remove Adobe launch daemons/agents ==="
for dir in "/Library/LaunchDaemons" "/Library/LaunchAgents" "$HOME_DIR/Library/LaunchAgents"; do
  [ -d "$dir" ] || continue
  ls "$dir"/com.adobe.* 2>/dev/null | while read -r plist; do
    [ -e "$plist" ] || continue
    if [ "$FORCE" -eq 1 ]; then launchctl bootout "system/$(basename "$plist" .plist)" 2>/dev/null; launchctl unload "$plist" 2>/dev/null; fi
    rm_path "$plist" "${plist#$HOME_DIR/}"
  done
done
echo ""

# ---------- app bundles ----------
echo "=== STEP: remove application bundles ==="
ls -d /Applications/Adobe* "/Applications/Utilities/Adobe Creative Cloud" 2>/dev/null | while read -r app; do
  if [ "$RM_ALL" -eq 0 ] && is_reader "$(basename "$app")"; then echo "  keep   $app (Acrobat Reader)"; continue; fi
  rm_path "$app" "$app"
done
echo ""

# ---------- library leftovers (com.adobe is Adobe's reverse-domain; safe, but keep Reader) ----------
echo "=== STEP: remove Adobe ~/Library and /Library leftovers ==="
LIBS="$HOME_DIR/Library /Library"
for L in $LIBS; do
  [ -d "$L" ] || continue
  needsudo=0; [ "$L" = "/Library" ] && needsudo=1
  # Application Support / Logs (whole Adobe folders)
  for sub in "Application Support/Adobe" "Logs/Adobe" "Caches/Adobe" "Caches/com.adobe.AdobeCreativeCloud"; do
    p="$L/$sub"
    if [ -e "$p" ]; then
      if [ "$needsudo" -eq 1 ] && [ "$(id -u)" -ne 0 ]; then echo "  WOULD remove ${p} (needs sudo)"; else rm_path "$p" "$p"; fi
    fi
  done
  # com.adobe.* prefs / containers / caches (keep Reader unless --remove-all)
  for base in "$L/Preferences" "$L/Containers" "$L/Caches" "$L/HTTPStorages" "$L/Application Scripts"; do
    [ -d "$base" ] || continue
    ls -d "$base"/com.adobe.* 2>/dev/null | while read -r item; do
      bn=$(basename "$item")
      if [ "$RM_ALL" -eq 0 ] && is_reader "$bn"; then echo "  keep   ${item} (Acrobat Reader)"; continue; fi
      if [ "$needsudo" -eq 1 ] && [ "$(id -u)" -ne 0 ]; then echo "  WOULD remove ${item} (needs sudo)"; else rm_path "$item" "$item"; fi
    done
  done
done
echo ""

# ---------- package receipts ----------
echo "=== STEP: forget Adobe package receipts ==="
if [ "$(id -u)" -eq 0 ]; then
  pkgutil --pkgs 2>/dev/null | grep -i "com.adobe" | while read -r pkg; do
    if [ "$RM_ALL" -eq 0 ] && is_reader "$pkg"; then continue; fi
    if [ "$FORCE" -eq 1 ]; then pkgutil --forget "$pkg" >/dev/null 2>&1 && log "forgot receipt $pkg"; else echo "  WOULD forget receipt $pkg"; fi
  done
else echo "  (needs sudo — skipped)"; fi
echo ""

# ---------- hosts (optional) ----------
if [ "$CLEAN_HOSTS" -eq 1 ]; then
  echo "=== STEP: clean Adobe license-blocking entries from /etc/hosts ==="
  if grep -iq adobe /etc/hosts 2>/dev/null; then
    grep -i adobe /etc/hosts | sed 's/^/    found: /'
    if [ "$(id -u)" -ne 0 ]; then echo "  (needs sudo to edit /etc/hosts)"
    elif [ "$FORCE" -eq 1 ]; then cp /etc/hosts "/etc/hosts.bak-$STAMP"; grep -iv adobe /etc/hosts > /tmp/hosts.clean && cat /tmp/hosts.clean > /etc/hosts && rm -f /tmp/hosts.clean; log "backed up /etc/hosts and removed Adobe lines"
    else echo "  WOULD back up /etc/hosts and remove Adobe lines"; fi
  else echo "  No Adobe entries in /etc/hosts."; fi
  echo ""
fi

# ---------- licensing + sign-in (forces re-auth) ----------
echo "=== STEP: clear licensing + sign-in (forces re-authentication) ==="
for p in "$HOME_DIR/Library/Application Support/Adobe/OOBE" \
         "/Library/Application Support/Adobe/SLStore" \
         "/Library/Application Support/Adobe/SLCache"; do
  if [ -e "$p" ]; then
    if echo "$p" | grep -q "^/Library" && [ "$(id -u)" -ne 0 ]; then echo "  WOULD clear $p (needs sudo)"; else rm_path "$p" "$p"; fi
  fi
done
# Keychain Adobe items
echo "Adobe User Info|Adobe App Info|com.adobe.adobeid" | tr '|' '\n' | while read -r label; do
  if security find-generic-password -l "$label" >/dev/null 2>&1; then
    if [ "$FORCE" -eq 1 ]; then while security delete-generic-password -l "$label" >/dev/null 2>&1; do :; done; log "cleared keychain item: $label"
    else echo "  WOULD clear keychain item: $label"; fi
  fi
done

echo ""
if [ "$FORCE" -eq 1 ]; then
  echo "Complete. Action log: $LOGFILE"
  echo "[!] Restart the Mac, then reinstall Creative Cloud; first launch requires a fresh sign-in."
  echo "Official deep-clean fallback for stubborn cases: Adobe Creative Cloud Cleaner Tool."
else
  echo "Dry run complete. Re-run with sudo and --force to apply."
  echo "Tip: --clean-hosts removes activation-blocking host entries; --remove-all also removes Acrobat Reader."
fi
