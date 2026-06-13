#!/bin/bash
# SYNOPSIS: Autostart & persistence audit: launch agents/daemons, login items, cron, and
# config profiles - third-party items listed, suspicious paths flagged. Read-only.
# USAGE: bash persistence_audit.sh   (sudo also lists installed configuration profiles)

echo "=== Startup & Persistence Audit (macOS) ==="
echo "Host: $(hostname -s)  |  User: $(whoami)"

flag_path(){ echo "$1" | grep -qiE "/tmp/|/private/tmp/|/Users/Shared/|/Downloads/|/Library/Caches/|osascript|/var/folders/|curl " && echo "  [!]" || echo ""; }

echo ""
echo "=== LaunchAgents / LaunchDaemons (third-party) ==="
for d in /Library/LaunchAgents /Library/LaunchDaemons "$HOME/Library/LaunchAgents"; do
  [ -d "$d" ] || continue
  echo "  [$d]"
  for p in "$d"/*.plist; do
    [ -e "$p" ] || continue
    LBL=$(basename "$p")
    PROG=$(defaults read "$p" ProgramArguments 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g')
    [ -z "$PROG" ] && PROG=$(defaults read "$p" Program 2>/dev/null)
    F=$(flag_path "$PROG")
    echo "    ${LBL}${F}"
    [ -n "$PROG" ] && echo "        -> $(echo "$PROG" | cut -c1-140)"
  done
done
echo "  (/System/Library/Launch* omitted - Apple-signed OS components)"

echo ""
echo "=== Login Items ==="
LI=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null)
if [ -n "$LI" ]; then
  echo "$LI" | tr ',' '\n' | sed 's/^ */  - /' | grep -v '^  - $'
else
  echo "  (none, or macOS blocked the query - on first run approve 'control System Events' for the terminal)"
fi

echo ""
echo "=== cron ==="
crontab -l 2>/dev/null | grep -v '^#' | grep -v '^[[:space:]]*$' | sed 's/^/  (user) /'
for c in /etc/crontab /usr/lib/cron/tabs/*; do
  [ -f "$c" ] && { echo "  [$c]"; grep -v '^#' "$c" 2>/dev/null | sed 's/^/    /'; }
done

echo ""
echo "=== StartupItems / periodic ==="
ls -1 /Library/StartupItems 2>/dev/null | sed 's/^/  StartupItem: /'
ls -1 /etc/periodic/*/* 2>/dev/null | sed 's/^/  periodic: /' | head -12

echo ""
echo "=== Configuration Profiles (MDM / manual) ==="
if [ "$(id -u)" -eq 0 ]; then
  profiles -P 2>/dev/null | sed 's/^/  /' | head -20
else
  echo "  (run with sudo to list installed profiles: sudo profiles -P)"
fi

echo ""
echo "[i] [!] = path in tmp/Shared/Downloads/caches or uses a script host. Not proof of malware - investigate."
