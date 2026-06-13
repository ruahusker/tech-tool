#!/bin/bash
# SYNOPSIS: Back up a user's key folders before a wipe/migration. PREVIEWS sizes by default;
# add --force --dest <path> to copy (rsync, source untouched).
# USAGE: bash backup_user_data.sh                          (preview current user)
#        bash backup_user_data.sh --user alice             (preview another user)
#        bash backup_user_data.sh --force --dest /Volumes/Backup
#        options: --all (entire home folder instead of common folders)

USER_NAME="$(whoami)"; DEST=""; FORCE=0; ALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --user) USER_NAME="$2"; shift;;
    --dest) DEST="$2"; shift;;
    --force) FORCE=1;;
    --all) ALL=1;;
  esac; shift
done

HOME_DIR="/Users/$USER_NAME"
[ -d "$HOME_DIR" ] || { echo "[!] No home folder at $HOME_DIR"; exit 1; }

if [ "$ALL" -eq 1 ]; then
  FOLDERS=("")
else
  FOLDERS=("Desktop" "Documents" "Downloads" "Pictures" "Movies" "Music" "Library/Safari" "Library/Application Support/Google/Chrome/Default/Bookmarks")
fi

MODE="PREVIEW (add --force --dest <path> to copy)"; [ "$FORCE" -eq 1 ] && MODE="EXECUTE"
echo "=== Backup User Data (macOS) ==="
echo "Mode: $MODE  |  User: $USER_NAME  |  Source: $HOME_DIR"
echo ""

echo "=== Folder Sizes ==="
TOTAL_K=0
for f in "${FOLDERS[@]}"; do
  if [ -z "$f" ]; then P="$HOME_DIR"; LABEL="(entire home)"; else P="$HOME_DIR/$f"; LABEL="$f"; fi
  if [ -e "$P" ]; then
    SZ=$(du -sk "$P" 2>/dev/null | awk '{print $1}')
    [ -n "$SZ" ] && TOTAL_K=$((TOTAL_K + SZ))
    MB=$(echo "${SZ:-0}" | awk '{printf "%.1f", $1/1024}')
    printf "  %-52s %9s MB\n" "$LABEL" "$MB"
  else
    printf "  %-52s %9s\n" "$LABEL" "(missing)"
  fi
done
TOTAL_MB=$(echo "$TOTAL_K" | awk '{printf "%.1f", $1/1024}')
printf "  %-52s %9s MB\n" "TOTAL" "$TOTAL_MB"

if [ "$FORCE" -eq 0 ]; then echo ""; echo "Preview only. Re-run with --force --dest <path> to copy."; exit 0; fi
[ -z "$DEST" ] && { echo ""; echo "[!] --force requires --dest <path>."; exit 1; }
[ -d "$DEST" ] || { echo "[!] Destination not found: $DEST"; exit 1; }

STAMP=$(date +%Y%m%d-%H%M%S)
TARGET="$DEST/$(hostname -s)_${USER_NAME}_${STAMP}"
mkdir -p "$TARGET"
LOGDIR="$(cd "$(dirname "$0")/.." && pwd)/collections"
mkdir -p "$LOGDIR" 2>/dev/null
LOG="$LOGDIR/$(hostname -s)-${USER_NAME}-backup-${STAMP}.log"

echo ""
echo "Copying to: $TARGET"
for f in "${FOLDERS[@]}"; do
  if [ -z "$f" ]; then SRC="$HOME_DIR/"; SUB=""; else SRC="$HOME_DIR/$f"; SUB="$f"; fi
  [ -e "$SRC" ] || continue
  echo "  rsync ${SUB:-home} ..."
  rsync -a "$SRC" "$TARGET/$SUB" >>"$LOG" 2>&1
done
echo "Done. Copied to $TARGET"
echo "Log: $LOG"
echo "Open a few files from the backup before wiping the source."
