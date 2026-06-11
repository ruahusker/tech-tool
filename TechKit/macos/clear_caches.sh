#!/bin/bash
# SYNOPSIS: Clean user caches, old logs, and optionally Trash. DRY-RUN BY DEFAULT.
# DESTRUCTIVE (mildly). Without --force only reports sizes. Apps rebuild caches on next launch.
# Deliberately NOT touched: browser profiles (passwords/cookies), app data, system caches.
# USAGE:
#   bash clear_caches.sh                    # report what would be freed
#   bash clear_caches.sh --force            # clean user caches + logs older than 30 days
#   bash clear_caches.sh --force --trash    # also empty this user's Trash

FORCE=0; TRASH=0
for ARG in "$@"; do
    case "$ARG" in
        --force) FORCE=1;;
        --trash) TRASH=1;;
    esac
done
MODE="DRY RUN (add --force to delete)"; [ "$FORCE" -eq 1 ] && MODE="EXECUTE"
echo "Mode: $MODE"
echo ""

TOTAL_KB=0

size_kb() { du -sk "$1" 2>/dev/null | cut -f1; }

# 1. User caches (rebuilt automatically)
CACHE_KB=$(size_kb "$HOME/Library/Caches")
CACHE_KB=${CACHE_KB:-0}
TOTAL_KB=$((TOTAL_KB + CACHE_KB))
if [ "$FORCE" -eq 1 ]; then
    # delete contents not the dir; in-use files fail silently and are kept
    find "$HOME/Library/Caches" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
    AFTER_KB=$(size_kb "$HOME/Library/Caches"); AFTER_KB=${AFTER_KB:-0}
    echo "  CLEANED      $(( (CACHE_KB - AFTER_KB) / 1024 )) MB  user caches (~/Library/Caches), $((AFTER_KB/1024)) MB in-use kept"
else
    echo "  WOULD CLEAN  $((CACHE_KB/1024)) MB  user caches (~/Library/Caches)"
fi

# 2. Old user logs (>30 days)
OLD_LOGS=$(find "$HOME/Library/Logs" -type f -mtime +30 2>/dev/null)
LOGS_KB=0
if [ -n "$OLD_LOGS" ]; then
    LOGS_KB=$(echo "$OLD_LOGS" | tr '\n' '\0' | xargs -0 du -k 2>/dev/null | awk '{s+=$1} END {print s+0}')
fi
TOTAL_KB=$((TOTAL_KB + LOGS_KB))
if [ "$FORCE" -eq 1 ] && [ -n "$OLD_LOGS" ]; then
    echo "$OLD_LOGS" | tr '\n' '\0' | xargs -0 rm -f 2>/dev/null
    echo "  CLEANED      $((LOGS_KB/1024)) MB  user logs older than 30 days"
else
    echo "  WOULD CLEAN  $((LOGS_KB/1024)) MB  user logs older than 30 days"
fi

# 3. Saved application state (fixes some 'app won't open' issues too)
SAS_KB=$(size_kb "$HOME/Library/Saved Application State"); SAS_KB=${SAS_KB:-0}
TOTAL_KB=$((TOTAL_KB + SAS_KB))
if [ "$FORCE" -eq 1 ]; then
    find "$HOME/Library/Saved Application State" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
    echo "  CLEANED      $((SAS_KB/1024)) MB  saved application state"
else
    echo "  WOULD CLEAN  $((SAS_KB/1024)) MB  saved application state"
fi

# 4. Trash (opt-in)
if [ "$TRASH" -eq 1 ]; then
    TRASH_KB=$(size_kb "$HOME/.Trash"); TRASH_KB=${TRASH_KB:-0}
    TOTAL_KB=$((TOTAL_KB + TRASH_KB))
    if [ "$FORCE" -eq 1 ]; then
        find "$HOME/.Trash" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
        echo "  EMPTIED      $((TRASH_KB/1024)) MB  Trash"
    else
        echo "  WOULD EMPTY  $((TRASH_KB/1024)) MB  Trash"
    fi
fi

echo ""
if [ "$FORCE" -eq 1 ]; then echo "Done. Freed up to $((TOTAL_KB/1024/1024)) GB (some in-use files kept)."
else echo "Reclaimable: about $((TOTAL_KB/1024/1024)) GB. Re-run with --force to clean."; fi
echo "Bigger wins are usually in find_large_files.sh (iOS backups, Xcode, Docker, Downloads)."
