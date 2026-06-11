#!/bin/bash
# SYNOPSIS: macOS update posture: version, available updates, update history, auto-update settings.
# Read-only. The 'softwareupdate -l' check needs network and can take ~30s.
# USAGE: bash update_status.sh [--check]   (--check queries Apple for available updates)

echo "=== CURRENT VERSION ==="
echo "  $(sw_vers -productName) $(sw_vers -productVersion) (build $(sw_vers -buildVersion))"

echo ""
echo "=== UPDATE HISTORY (last 15) ==="
softwareupdate --history 2>/dev/null | head -18 | sed 's/^/  /'
if [ $? -ne 0 ] || [ -z "$(softwareupdate --history 2>/dev/null)" ]; then
    echo "  (no history via softwareupdate; checking install.log)"
    grep -E "Installed|SUOSUShimController" /var/log/install.log 2>/dev/null | tail -10 | sed 's/^/  /'
fi

echo ""
echo "=== AUTO-UPDATE SETTINGS ==="
PLIST="/Library/Preferences/com.apple.SoftwareUpdate"
for KEY in AutomaticCheckEnabled AutomaticDownload AutomaticallyInstallMacOSUpdates ConfigDataInstall CriticalUpdateInstall; do
    VAL=$(defaults read "$PLIST" "$KEY" 2>/dev/null)
    echo "  ${KEY}: ${VAL:-not set}"
done
APPSTORE=$(defaults read /Library/Preferences/com.apple.commerce AutoUpdate 2>/dev/null)
echo "  App Store AutoUpdate: ${APPSTORE:-not set}"
if [ "$(defaults read "$PLIST" CriticalUpdateInstall 2>/dev/null)" = "0" ]; then
    echo "  [!] Critical/security auto-install is OFF."
fi

if [ "$1" = "--check" ]; then
    echo ""
    echo "=== AVAILABLE UPDATES (querying Apple, ~30s) ==="
    softwareupdate -l 2>&1 | sed 's/^/  /'
else
    echo ""
    echo "Run with --check to query Apple for pending updates (needs internet, ~30s)."
fi

echo ""
echo "Hints: stuck updates -> free 20+ GB, reboot, retry; still stuck -> boot Safe Mode and retry,"
echo "or download the full installer: softwareupdate --fetch-full-installer --full-installer-version <ver>"
