#!/bin/bash
# SYNOPSIS: Inventory installed software: /Applications (with versions), Homebrew, and App Store apps.
# Read-only. Use to see what's installed, or what changed recently (--sort-date).
# USAGE: bash installed_software.sh [--sort-date] [search-term]

SORT_DATE=0; SEARCH=""
for a in "$@"; do
  case "$a" in
    --sort-date) SORT_DATE=1;;
    *) SEARCH="$a";;
  esac
done

echo "=== APPLICATIONS (/Applications) ==="
# Build "date<TAB>name<TAB>version" lines, then sort.
tmp=$(mktemp)
for app in /Applications/*.app /Applications/*/*.app; do
  [ -d "$app" ] || continue
  name=$(basename "$app" .app)
  if [ -n "$SEARCH" ]; then echo "$name" | grep -iq "$SEARCH" || continue; fi
  plist="$app/Contents/Info.plist"
  ver=$(defaults read "$plist" CFBundleShortVersionString 2>/dev/null)
  # modification date of the app bundle (proxy for install/update date)
  mdate=$(stat -f "%Sm" -t "%Y-%m-%d" "$app" 2>/dev/null)
  printf "%s\t%s\t%s\n" "${mdate:-0000-00-00}" "$name" "${ver:-?}" >> "$tmp"
done
if [ "$SORT_DATE" -eq 1 ]; then sort -r "$tmp" > "$tmp.s"; else sort -t$'\t' -k2 -f "$tmp" > "$tmp.s"; fi
count=$(wc -l < "$tmp.s" | tr -d ' ')
awk -F'\t' '{printf "  %s  %-42s %s\n", $1, substr($2,1,42), $3}' "$tmp.s"
rm -f "$tmp" "$tmp.s"
echo "  ($count applications$([ -n "$SEARCH" ] && echo " matching \"$SEARCH\""))"

echo ""
echo "=== HOMEBREW PACKAGES ==="
if command -v brew >/dev/null 2>&1; then
  echo "  Formulae:"; brew list --formula --versions 2>/dev/null | sed 's/^/    /' | { [ -n "$SEARCH" ] && grep -i "$SEARCH" || cat; } | head -100
  echo "  Casks:";    brew list --cask --versions 2>/dev/null | sed 's/^/    /' | { [ -n "$SEARCH" ] && grep -i "$SEARCH" || cat; } | head -100
else
  echo "  (Homebrew not installed)"
fi

echo ""
echo "=== MAC APP STORE APPS ==="
find /Applications -maxdepth 3 -path "*Contents/_MASReceipt/receipt" 2>/dev/null | sed 's#/Contents/_MASReceipt/receipt##; s#.*/##; s#\.app$##' | sort | sed 's/^/  /' | { [ -n "$SEARCH" ] && grep -i "$SEARCH" || cat; }

echo ""
echo "Hint: --sort-date lists apps newest-first (useful for 'what changed right before the problem')."
echo "Deeper inventory (slow, includes everything): system_profiler SPApplicationsDataType"
