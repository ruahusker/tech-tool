#!/bin/bash
# SYNOPSIS: Disable (or delete) local users with no login in N days. DRY-RUN BY DEFAULT.
# DESTRUCTIVE - requires sudo for --force. Safety rails:
#   - Default action DISABLE (reversible); delete requires --delete explicitly.
#   - Never touches: uid<500, the invoking user, or admin-group members (no override exists).
#   - Accounts absent from the login log are SKIPPED by default (wtmp rotates; absence
#     is weak evidence). Override with --include-unknown after verifying manually.
#   - Every action appended to TechKit/collections/<host>-user-cleanup-<ts>.log
# USAGE:
#   bash remove_inactive_users.sh [days]                      # dry run (default 90)
#   sudo bash remove_inactive_users.sh 90 --force             # disable inactive users
#   sudo bash remove_inactive_users.sh 180 --delete --remove-home --force
#   options: --exclude user1,user2  --include-unknown

DAYS=90; FORCE=0; DELETE=0; REMOVE_HOME=0; INCLUDE_UNKNOWN=0; EXCLUDE=""
for ARG in "$@"; do
    case "$ARG" in
        --force) FORCE=1;;
        --delete) DELETE=1;;
        --remove-home) REMOVE_HOME=1;;
        --include-unknown) INCLUDE_UNKNOWN=1;;
        --exclude=*) EXCLUDE="${ARG#--exclude=}";;
        --exclude) ;; # handled positionally below if someone uses '--exclude a,b'
        [0-9]*) DAYS="$ARG";;
    esac
done
# support "--exclude a,b" style
PREV=""
for ARG in "$@"; do
    [ "$PREV" = "--exclude" ] && EXCLUDE="$ARG"
    PREV="$ARG"
done

CALLER="${SUDO_USER:-$(whoami)}"
ACTION="DISABLE"; [ "$DELETE" -eq 1 ] && ACTION="DELETE"
MODE="DRY RUN (no changes; add --force to apply)"; [ "$FORCE" -eq 1 ] && MODE="EXECUTE"

if [ "$FORCE" -eq 1 ] && [ "$(id -u)" -ne 0 ]; then
    echo "[!] --force requires sudo. Aborting."; exit 1
fi

CUTOFF_EPOCH=$(( $(date +%s) - DAYS*86400 ))
ADMINS=$(dscl . -read /Groups/admin GroupMembership 2>/dev/null | sed 's/GroupMembership: //')
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LOGFILE="$SCRIPT_DIR/../collections/$(hostname -s)-user-cleanup-$(date +%Y%m%d-%H%M%S).log"

log_action() {
    echo "  $1"
    [ "$FORCE" -eq 1 ] && echo "$(date '+%Y-%m-%d %H:%M:%S')  $1" >> "$LOGFILE" 2>/dev/null
}

echo "Mode: $MODE"
echo "Action: $ACTION users with no login in $DAYS days  |  Host: $(hostname -s)"
echo ""
echo "=== EVALUATION ==="

CANDIDATES=""
for USER in $(dscl . -list /Users UniqueID 2>/dev/null | awk '$2 >= 500 {print $1}'); do
    # protections
    if [ "$USER" = "$CALLER" ]; then echo "  SKIP  $USER  (current user)"; continue; fi
    echo ",$EXCLUDE," | grep -q ",$USER," && { echo "  SKIP  $USER  (excluded)"; continue; }
    if echo "$ADMINS" | grep -qw "$USER"; then
        echo "  SKIP  $USER  (admin group - admin accounts are never touched)"; continue
    fi
    DISABLED=$(dscl . -read "/Users/$USER" AuthenticationAuthority 2>/dev/null | grep -c DisabledUser)
    if [ "$DISABLED" -gt 0 ] && [ "$DELETE" -eq 0 ]; then echo "  SKIP  $USER  (already disabled)"; continue; fi

    # last login: try wtmp via 'last'
    LASTLINE=$(last -1 "$USER" 2>/dev/null | grep -v "^wtmp" | grep -v "^$" | head -1)
    if [ -z "$LASTLINE" ]; then
        if [ "$INCLUDE_UNKNOWN" -eq 0 ]; then
            echo "  SKIP  $USER  (no login record - wtmp rotates; use --include-unknown only after verifying)"
            continue
        fi
        CANDIDATES="$CANDIDATES $USER"; echo "  MATCH $USER  (no login record, --include-unknown set)"
        continue
    fi
    # parse "user tty date..." -> epoch via date -j (BSD date)
    LASTDATE=$(echo "$LASTLINE" | awk '{print $3, $4, $5, $6}')
    LAST_EPOCH=$(date -j -f "%a %b %d %H:%M" "$LASTDATE" +%s 2>/dev/null)
    if [ -z "$LAST_EPOCH" ]; then
        echo "  SKIP  $USER  (could not parse last-login date: $LASTDATE)"
        continue
    fi
    if [ "$LAST_EPOCH" -lt "$CUTOFF_EPOCH" ]; then
        CANDIDATES="$CANDIDATES $USER"; echo "  MATCH $USER  (last login $LASTDATE)"
    else
        echo "  SKIP  $USER  (active: last login $LASTDATE)"
    fi
done

echo ""
if [ -z "$CANDIDATES" ]; then echo "No candidates. Nothing to do."; exit 0; fi

echo "=== ${ACTION} ==="
for USER in $CANDIDATES; do
    if [ "$FORCE" -eq 0 ]; then
        echo "  WOULD $ACTION $USER"
        continue
    fi
    if [ "$DELETE" -eq 1 ]; then
        if [ "$REMOVE_HOME" -eq 1 ]; then
            sysadminctl -deleteUser "$USER" 2>&1 | tail -1 >/dev/null && log_action "DELETED $USER (home removed)" || log_action "FAILED delete $USER"
        else
            sysadminctl -deleteUser "$USER" -keepHome 2>&1 | tail -1 >/dev/null && log_action "DELETED $USER (home kept at /Users/$USER)" || log_action "FAILED delete $USER"
        fi
    else
        pwpolicy -u "$USER" -disableuser >/dev/null 2>&1 && log_action "DISABLED $USER" || log_action "FAILED disable $USER"
    fi
done

if [ "$FORCE" -eq 1 ]; then echo ""; echo "Action log: $LOGFILE"
else echo ""; echo "Dry run complete. Re-run with sudo and --force to apply."; fi
echo "Re-enable a disabled user: sudo pwpolicy -u <user> -enableuser"
