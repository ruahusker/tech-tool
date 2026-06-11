#!/bin/bash
# SYNOPSIS: Everything that launches at boot/login: LaunchDaemons, LaunchAgents, login items, cron.
# Read-only. The slow-startup and persistence-hunting script.
# USAGE: bash startup_items.sh

list_plists() {
    DIR="$1"; LABEL="$2"
    if [ -d "$DIR" ]; then
        FOUND=$(ls "$DIR"/*.plist 2>/dev/null)
        if [ -n "$FOUND" ]; then
            echo "  [$LABEL] $DIR"
            for P in $DIR/*.plist; do
                PROG=$(plutil -extract ProgramArguments.0 raw "$P" 2>/dev/null || plutil -extract Program raw "$P" 2>/dev/null)
                DISABLED=$(plutil -extract Disabled raw "$P" 2>/dev/null)
                FLAG=""
                [ "$DISABLED" = "true" ] && FLAG=" (disabled)"
                echo "    $(basename "$P" .plist)${FLAG} -> ${PROG:-?}"
            done
        fi
    fi
}

echo "=== THIRD-PARTY LAUNCH DAEMONS (run as root at boot) ==="
list_plists "/Library/LaunchDaemons" "system"

echo ""
echo "=== THIRD-PARTY LAUNCH AGENTS (run at login) ==="
list_plists "/Library/LaunchAgents" "all users"
list_plists "$HOME/Library/LaunchAgents" "this user"

echo ""
echo "=== LOGIN ITEMS (System Settings list) ==="
osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | tr ',' '\n' | sed 's/^ */  /' \
    || echo "  (Automation permission denied - check System Settings > General > Login Items manually)"

echo ""
echo "=== BACKGROUND TASK MANAGEMENT (macOS 13+) ==="
if command -v sfltool >/dev/null 2>&1; then
    sfltool dumpbtm 2>/dev/null | grep -E "Name:|Type:|Disposition:" | head -60 | sed 's/^ */  /'
    [ $? -ne 0 ] && echo "  (sfltool dumpbtm needs sudo for full output: sudo sfltool dumpbtm)"
fi

echo ""
echo "=== RUNNING NON-APPLE LAUNCHD JOBS ==="
launchctl list 2>/dev/null | grep -v "com.apple." | sed 's/^/  /' | head -40

echo ""
echo "=== CRON JOBS ==="
CRON=$(crontab -l 2>/dev/null)
if [ -n "$CRON" ]; then echo "$CRON" | sed 's/^/  /'; else echo "  None for $(whoami)."; fi

echo ""
echo "Hints: disable an agent: 'launchctl bootout gui/\$(id -u) <path.plist>' (user) or sudo launchctl bootout system <path.plist> (daemon)."
echo "Malware favorites: ~/Library/LaunchAgents with random names pointing into /tmp or ~/Library/Application Support."
