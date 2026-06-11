#!/bin/bash
# SYNOPSIS: Find what is eating disk space: largest files, folders, and known space hogs.
# Read-only. Uses Spotlight (mdfind) when available for speed, falls back to find.
# USAGE: bash find_large_files.sh [path] [min_size_mb] [top_n]   (defaults: /Users 200 25)

SCAN_PATH="${1:-/Users}"
MIN_MB="${2:-200}"
TOP_N="${3:-25}"

echo "Scanning $SCAN_PATH for files >= ${MIN_MB} MB..."
echo ""
echo "=== TOP FILES ==="
if mdutil -s / 2>/dev/null | grep -q "Indexing enabled"; then
    mdfind -onlyin "$SCAN_PATH" "kMDItemFSSize > $((MIN_MB * 1048576))" 2>/dev/null \
        | head -500 | while IFS= read -r F; do
            SZ=$(stat -f%z "$F" 2>/dev/null)
            [ -n "$SZ" ] && printf "%012d\t%s\n" "$SZ" "$F"
        done | sort -rn | head "-$TOP_N" | awk -F'\t' '{printf "  %8.2f GB  %s\n", $1/1073741824, $2}'
else
    echo "  (Spotlight off - using find, slower)"
    find "$SCAN_PATH" -xdev -type f -size +"${MIN_MB}"M 2>/dev/null \
        | head -500 | while IFS= read -r F; do
            SZ=$(stat -f%z "$F" 2>/dev/null)
            [ -n "$SZ" ] && printf "%012d\t%s\n" "$SZ" "$F"
        done | sort -rn | head "-$TOP_N" | awk -F'\t' '{printf "  %8.2f GB  %s\n", $1/1073741824, $2}'
fi

echo ""
echo "=== FIRST-LEVEL FOLDER SIZES under $SCAN_PATH ==="
du -sh "$SCAN_PATH"/* 2>/dev/null | sort -rh | head -15 | sed 's/^/  /'

echo ""
echo "=== KNOWN SPACE HOGS ==="
for D in "$HOME/Library/Caches" "$HOME/Library/Developer" "$HOME/Downloads" "$HOME/.Trash" \
         "/Library/Caches" "/private/var/vm" "$HOME/Library/Application Support/MobileSync/Backup" \
         "$HOME/Library/Containers/com.docker.docker"; do
    [ -d "$D" ] || continue
    SZ=$(du -sk "$D" 2>/dev/null | cut -f1)
    [ -n "$SZ" ] && [ "$SZ" -gt 204800 ] && echo "  $(du -sh "$D" 2>/dev/null | cut -f1)  $D"
done
SNAPS=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c snapshots)

echo ""
echo "Hints: iOS backups (MobileSync) and ~/Library/Developer (Xcode) are the classic multi-GB surprises."
echo "Purgeable space held by APFS snapshots: tmutil listlocalsnapshots /  (thin with tmutil thinlocalsnapshots)."
echo "Use clear_caches.sh for safe cache cleanup."
