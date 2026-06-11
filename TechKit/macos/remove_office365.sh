#!/bin/bash
# SYNOPSIS: Deep uninstall of Microsoft 365 / Office for macOS, including the ~/Library leftovers
#           a drag-to-Trash misses, and clears cached sign-in/licensing so products re-authenticate.
# DESTRUCTIVE - DRY-RUN BY DEFAULT. Some steps need sudo (package receipts + system license).
#
# SAFETY:
#   - Never touches ~/Documents or any user file outside Office's own app-support locations.
#   - Outlook's LOCAL MAIL lives inside the Office group container. By default this PRESERVES it
#     (the "Outlook" profile data). Pass --remove-outlook-data to wipe it too (mail re-syncs for
#     Exchange/Microsoft 365 accounts; POP/local-only data would be lost — warn the user first).
#
# USAGE:
#   bash remove_office365.sh                          # preview a full deep uninstall
#   sudo bash remove_office365.sh --force             # full deep uninstall + clear sign-in
#   sudo bash remove_office365.sh --reset-activation-only --force   # just force re-sign-in, keep Office
#   options: --remove-outlook-data   --remove-all (also OneDrive/Teams)

FORCE=0; RESET_ONLY=0; RM_OUTLOOK=0; RM_ALL=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1;;
    --reset-activation-only) RESET_ONLY=1;;
    --remove-outlook-data) RM_OUTLOOK=1;;
    --remove-all) RM_ALL=1;;
  esac
done

CALLER="${SUDO_USER:-$(whoami)}"
HOME_DIR="$(eval echo ~"$CALLER")"
GROUP="$HOME_DIR/Library/Group Containers/UBF8T346G9.Office"
STAMP="$(date +%Y%m%d-%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOGFILE="$SCRIPT_DIR/../collections/$(hostname -s)-office-removal-$STAMP.log"
MODE="DRY RUN (preview only; add --force to apply)"; [ "$FORCE" -eq 1 ] && MODE="EXECUTE"

log() {
  echo "  $1"
  if [ "$FORCE" -eq 1 ]; then mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null; echo "$(date '+%Y-%m-%d %H:%M:%S')  $1" >> "$LOGFILE" 2>/dev/null; fi
}
# remove a path (file or dir) with dry-run support; arg2 = label
rm_path() {
  local p="$1" label="${2:-$1}"
  [ -e "$p" ] || return 0
  if [ "$FORCE" -eq 1 ]; then rm -rf "$p" 2>/dev/null && log "removed $label" || log "FAILED to remove $label"
  else echo "  WOULD remove $label"; fi
}

echo "=== Microsoft 365 / Office Deep Removal (macOS) ==="
echo "Mode: $MODE  |  User: $CALLER  |  $([ "$RESET_ONLY" -eq 1 ] && echo 'RESET ACTIVATION ONLY' || echo 'FULL UNINSTALL')"
[ "$(id -u)" -ne 0 ] && echo "Note: not running with sudo — package receipts and the system license file will be skipped (re-run with sudo for a complete clean)."
echo ""

# ---------- inventory ----------
echo "=== Installed Office apps ==="
for app in "Microsoft Word" "Microsoft Excel" "Microsoft PowerPoint" "Microsoft Outlook" "Microsoft OneNote" "OneDrive" "Microsoft Teams"; do
  P="/Applications/$app.app"
  if [ -d "$P" ]; then
    V=$(defaults read "$P/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
    echo "  $app  ${V:-(version n/a)}"
  fi
done
echo ""

# ---------- quit apps ----------
if [ "$RESET_ONLY" -eq 0 ]; then
  echo "=== STEP: quit Office apps ==="
  for proc in "Microsoft Word" "Microsoft Excel" "Microsoft PowerPoint" "Microsoft Outlook" "Microsoft OneNote" "Microsoft AutoUpdate" "Microsoft Error Reporting" "com.microsoft.OneNote"; do
    if pgrep -f "$proc" >/dev/null 2>&1; then
      if [ "$FORCE" -eq 1 ]; then osascript -e "quit app \"$proc\"" 2>/dev/null; sleep 1; pkill -f "$proc" 2>/dev/null; log "quit $proc"
      else echo "  WOULD quit $proc"; fi
    fi
  done
  echo ""
fi

# ---------- app bundles ----------
if [ "$RESET_ONLY" -eq 0 ]; then
  echo "=== STEP: remove application bundles ==="
  for app in "Microsoft Word" "Microsoft Excel" "Microsoft PowerPoint" "Microsoft Outlook" "Microsoft OneNote"; do
    rm_path "/Applications/$app.app" "/Applications/$app.app"
  done
  if [ "$RM_ALL" -eq 1 ]; then
    rm_path "/Applications/OneDrive.app" "/Applications/OneDrive.app"
    rm_path "/Applications/Microsoft Teams.app" "/Applications/Microsoft Teams.app"
  else
    echo "  (leaving OneDrive and Teams — pass --remove-all to remove them too)"
  fi
  echo ""
fi

# ---------- per-app containers / prefs / caches ----------
if [ "$RESET_ONLY" -eq 0 ]; then
  echo "=== STEP: remove ~/Library leftovers ==="
  L="$HOME_DIR/Library"
  # Decide if a com.microsoft.* item belongs to OFFICE (vs Edge/VSCode/OneDrive/Teams/Defender,
  # which must NOT be touched). Allowlist Office IDs; default to KEEP anything unrecognized.
  is_office_item() {
    local n; n=$(echo "$1" | tr 'A-Z' 'a-z')
    case "$n" in
      *vscode*|*edgemac*|*edgeupdate*|*onedrive*|*teams*|*defender*|*intune*|*companyportal*|*skype*|*remotedesktop*|*edgewebview*)
        return 1 ;;  # explicitly protected — never remove
      com.microsoft.word*|com.microsoft.excel*|com.microsoft.powerpoint*|com.microsoft.outlook*|\
      com.microsoft.onenote*|com.microsoft.office*|com.microsoft.office365*|com.microsoft.errorreporting*|\
      com.microsoft.rms*|com.microsoft.netlib*)
        return 0 ;;  # Office
      *) return 1 ;; # unknown Microsoft app — leave it alone
    esac
  }
  for base in "$L/Containers" "$L/Preferences" "$L/Caches" "$L/HTTPStorages" "$L/Application Scripts" "$L/Saved Application State"; do
    [ -d "$base" ] || continue
    ls -d "$base"/com.microsoft.* 2>/dev/null | while read -r item; do
      bn=$(basename "$item")
      if is_office_item "$bn"; then rm_path "$item" "${item#$HOME_DIR/}"
      else echo "  keep   ${item#$HOME_DIR/} (not Office)"; fi
    done
  done
  # Microsoft AutoUpdate is shared by Edge/Teams too — only remove with --remove-all
  if [ "$RM_ALL" -eq 1 ]; then
    rm_path "$L/Containers/com.microsoft.autoupdate2" "Library/Containers/com.microsoft.autoupdate2"
  fi
  echo ""

  echo "=== STEP: Office group containers (Outlook mail handled carefully) ==="
  # UBF8T346G9.ms and OfficeOsfWebHost have no user mail — safe to remove
  rm_path "$HOME_DIR/Library/Group Containers/UBF8T346G9.ms" "Group Containers/UBF8T346G9.ms"
  rm_path "$HOME_DIR/Library/Group Containers/UBF8T346G9.OfficeOsfWebHost" "Group Containers/UBF8T346G9.OfficeOsfWebHost"
  if [ -d "$GROUP" ]; then
    if [ "$RM_OUTLOOK" -eq 1 ]; then
      echo "  [!] --remove-outlook-data set: removing the ENTIRE Office group container (local Outlook mail will be deleted)."
      rm_path "$GROUP" "Group Containers/UBF8T346G9.Office"
    else
      echo "  Preserving Outlook mail data; removing the rest of the Office group container."
      ls -A "$GROUP" 2>/dev/null | while read -r item; do
        if [ "$item" = "Outlook" ]; then echo "  KEEP   Group Containers/UBF8T346G9.Office/Outlook (local mail — use --remove-outlook-data to wipe)";
        else rm_path "$GROUP/$item" "Group Containers/UBF8T346G9.Office/$item"; fi
      done
    fi
  fi
  echo ""
fi

# ---------- package receipts ----------
if [ "$RESET_ONLY" -eq 0 ]; then
  echo "=== STEP: forget package receipts ==="
  if [ "$(id -u)" -eq 0 ]; then
    pkgutil --pkgs 2>/dev/null | grep -i "com.microsoft" | while read -r pkg; do
      if [ "$FORCE" -eq 1 ]; then pkgutil --forget "$pkg" >/dev/null 2>&1 && log "forgot receipt $pkg"; else echo "  WOULD forget receipt $pkg"; fi
    done
  else
    echo "  (needs sudo — skipped)"
  fi
  echo ""
fi

# ---------- licensing + identity (forces re-authentication) ----------
echo "=== STEP: clear licensing + cached sign-in (forces re-authentication) ==="
# System volume/subscription license file (needs sudo)
for lic in "/Library/Preferences/com.microsoft.office.licensingV2.plist" \
           "/Library/Preferences/com.microsoft.office.licensing.plist"; do
  if [ -e "$lic" ]; then
    if [ "$(id -u)" -eq 0 ]; then rm_path "$lic" "$lic"
    else echo "  WOULD remove $lic (needs sudo)"; fi
  fi
done
# Keychain identity / license / token items — removing these forces a fresh sign-in
KC_LABELS="Microsoft Office Identities Cache 2|Microsoft Office Identities Cache 3|Microsoft Office Identities Settings 2|Microsoft Office Identities Settings 3|MicrosoftOfficeRMSCredential|Microsoft Office Ticket Cache|com.microsoft.adalcache|MSOpenTech.ADAL.1|MicrosoftAccount"
echo "$KC_LABELS" | tr '|' '\n' | while read -r label; do
  if security find-generic-password -l "$label" >/dev/null 2>&1; then
    if [ "$FORCE" -eq 1 ]; then
      while security delete-generic-password -l "$label" >/dev/null 2>&1; do :; done
      log "cleared keychain item: $label"
    else echo "  WOULD clear keychain item: $label"; fi
  fi
done

echo ""
if [ "$FORCE" -eq 1 ]; then
  echo "Complete. Action log: $LOGFILE"
  if [ "$RESET_ONLY" -eq 1 ]; then echo "Re-open any Office app; it will prompt to sign in / re-activate."
  else echo "[!] Restart the Mac. Then reinstall Microsoft 365; first launch will require a fresh sign-in."; fi
  echo "Official fallback for stubborn cases: Microsoft's 'License Removal Tool' and the support uninstall guide."
else
  echo "Dry run complete. Re-run with sudo and --force to apply."
  echo "Tip: --reset-activation-only fixes wrong-account/activation WITHOUT uninstalling."
fi
