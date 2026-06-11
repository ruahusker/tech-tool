#!/bin/bash
# SYNOPSIS: Security posture: SIP, Gatekeeper, FileVault, firewall, XProtect, admins, sharing services.
# Read-only. Some checks show more detail with sudo but all degrade gracefully.
# USAGE: bash security_status.sh

echo "=== CORE PROTECTIONS ==="
echo "  SIP (csrutil)   : $(csrutil status 2>/dev/null | head -1 | sed 's/System Integrity Protection status: //')"
echo "  Gatekeeper      : $(spctl --status 2>/dev/null)"
echo "  FileVault       : $(fdesetup status 2>/dev/null | head -1)"
FW=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)
echo "  App Firewall    : ${FW:-unknown}"
echo "$FW" | grep -qi "disabled" && echo "  [~] Application firewall is off (common default; enable for laptops on public networks)."
fdesetup status 2>/dev/null | grep -qi "Off" && echo "  [!] FileVault OFF - disk is unencrypted; a stolen laptop = stolen data."

echo ""
echo "=== XPROTECT / MRT (built-in anti-malware) ==="
XP="/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist"
[ -f "$XP" ] && echo "  XProtect version: $(defaults read "$XP" CFBundleShortVersionString 2>/dev/null)"
XPR="/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/Info.plist"
[ -f "$XPR" ] && echo "  XProtect Remediator: $(defaults read "$XPR" CFBundleShortVersionString 2>/dev/null)"

echo ""
echo "=== ADMIN USERS ==="
dscl . -read /Groups/admin GroupMembership 2>/dev/null | sed 's/GroupMembership: /  /' | tr ' ' '\n' | grep -v '^$' | grep -v GroupMembership | sed 's/^/  /' | sed 's/^  *root$/  root (built-in)/'

echo ""
echo "=== SHARING / REMOTE ACCESS ==="
# These read launchd state rather than systemsetup (which needs sudo)
check_service() {
    if launchctl print "system/$2" >/dev/null 2>&1; then echo "  $1: ENABLED"
    else echo "  $1: off"; fi
}
check_service "SSH (Remote Login)     " "com.openssh.sshd"
check_service "Screen Sharing         " "com.apple.screensharing"
check_service "File Sharing (SMB)     " "com.apple.smbd"
echo "  (ENABLED remote services on a personal Mac deserve a 'did you set this up?' question)"

echo ""
echo "=== KERNEL/SYSTEM EXTENSIONS (third-party) ==="
systemextensionsctl list 2>/dev/null | grep -v "^---" | grep -vE "^\s*$" | sed 's/^/  /' | head -15
KEXTS=$(kextstat 2>/dev/null | grep -v com.apple | tail -n +2)
[ -n "$KEXTS" ] && { echo "  Legacy kexts (non-Apple):"; echo "$KEXTS" | awk '{print "    "$6}'; }

echo ""
echo "=== QUARANTINE / RECENT DOWNLOADS SANITY ==="
ls -t "$HOME/Downloads" 2>/dev/null | head -5 | sed 's/^/  /'
echo "  (newest downloads above - relevant when investigating 'I clicked something')"
