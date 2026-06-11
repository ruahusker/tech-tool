#!/bin/bash
# SYNOPSIS: Clear the Microsoft Teams cache on macOS to fix freezes, blank screens, stale presence,
#           and login loops. Handles classic Teams and new Teams. DRY-RUN BY DEFAULT. No sudo.
# USAGE: bash clear_teams_cache.sh           (preview)
#        bash clear_teams_cache.sh --force   (apply)

FORCE=0; [ "$1" = "--force" ] && FORCE=1
MODE="DRY RUN (add --force to apply)"; [ "$FORCE" -eq 1 ] && MODE="EXECUTE"
echo "=== Clear Microsoft Teams Cache (macOS) ==="
echo "Mode: $MODE"
echo "Chats/teams live in the cloud and re-download — nothing of yours is lost."
echo ""

if [ "$FORCE" -eq 1 ]; then
  osascript -e 'quit app "Microsoft Teams"' 2>/dev/null; sleep 2; pkill -f "Microsoft Teams" 2>/dev/null; pkill -f "MSTeams" 2>/dev/null; sleep 1
else
  echo "  WOULD quit Microsoft Teams"
fi

clear_path() {
  local p="$1" label="$2"
  [ -e "$p" ] || return 0
  local sz; sz=$(du -sk "$p" 2>/dev/null | cut -f1); sz=$(( ${sz:-0} / 1024 ))
  if [ "$FORCE" -eq 1 ]; then rm -rf "$p" 2>/dev/null && echo "  CLEARED $label (${sz} MB)"; else echo "  WOULD clear $label (${sz} MB)"; fi
}

echo "=== Classic Teams ==="
C="$HOME/Library/Application Support/Microsoft/Teams"
if [ -d "$C" ]; then
  for sub in "Cache" "blob_storage" "databases" "GPUCache" "IndexedDB" "Local Storage" "tmp" "Service Worker" "Application Cache" "Code Cache"; do
    clear_path "$C/$sub" "Teams/$sub"
  done
else echo "  (classic Teams not present)"; fi

echo ""
echo "=== New Teams ==="
# new Teams stores cache in its app container / group container
for p in "$HOME/Library/Group Containers/UBF8T346G9.com.microsoft.teams" \
         "$HOME/Library/Containers/com.microsoft.teams2/Data/Library/Caches"; do
  clear_path "$p" "$(echo "$p" | sed "s#$HOME/##")"
done

echo ""
if [ "$FORCE" -eq 1 ]; then echo "Done. Relaunch Teams; first start will be slower while it rebuilds the cache."
else echo "Dry run complete. Re-run with --force to apply."; fi
