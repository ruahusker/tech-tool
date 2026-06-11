#!/bin/bash
# SYNOPSIS: Local user inventory: accounts, last logins, home folder sizes, admin membership.
# Read-only. The reconnaissance step before remove_inactive_users.sh.
# USAGE: bash user_account_report.sh [--sizes]   (--sizes measures home folders; slower)

echo "=== LOCAL USERS (uid >= 500) ==="
ADMINS=$(dscl . -read /Groups/admin GroupMembership 2>/dev/null | sed 's/GroupMembership: //')
dscl . -list /Users UniqueID 2>/dev/null | awk '$2 >= 500 {print $1, $2}' | while read -r USER UID_; do
    HOMEDIR=$(dscl . -read "/Users/$USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    IS_ADMIN="no"
    echo "$ADMINS" | grep -qw "$USER" && IS_ADMIN="YES"
    # last login from wtmp (rotates - 'never in log' may just mean 'not recently')
    LAST=$(last -1 "$USER" 2>/dev/null | head -1 | grep -v "^$" | grep -v wtmp)
    if [ -n "$LAST" ]; then
        LAST_FMT=$(echo "$LAST" | awk '{print $3, $4, $5, $6}')
    else
        LAST_FMT="not in login log"
    fi
    echo "  $USER (uid $UID_)  admin=$IS_ADMIN  last=$LAST_FMT  home=$HOMEDIR"
done
echo "  Note: 'last' reads wtmp which rotates - treat 'not in log' as 'no recent login', verify before deleting."

echo ""
echo "=== CURRENTLY LOGGED IN ==="
who | sed 's/^/  /'

echo ""
echo "=== HOME FOLDER SIZES ==="
if [ "$1" = "--sizes" ]; then
    du -sh /Users/* 2>/dev/null | sort -rh | sed 's/^/  /'
else
    ls -1 /Users 2>/dev/null | grep -v "Shared" | sed 's/^/  /'
    echo "  (run with --sizes to measure folder sizes - can take minutes)"
fi

echo ""
echo "=== ADMIN GROUP ==="
echo "  $ADMINS"

echo ""
echo "=== HIDDEN / DISABLED ACCOUNT MARKERS ==="
dscl . -list /Users UniqueID 2>/dev/null | awk '$2 >= 500 {print $1}' | while read -r USER; do
    HIDDEN=$(dscl . -read "/Users/$USER" IsHidden 2>/dev/null | awk '{print $2}')
    AUTH=$(dscl . -read "/Users/$USER" AuthenticationAuthority 2>/dev/null | grep -c DisabledUser)
    [ "$HIDDEN" = "1" ] && echo "  $USER: hidden"
    [ "$AUTH" -gt 0 ] && echo "  $USER: DISABLED"
done
echo "  (no output above = no hidden/disabled local accounts)"
