#!/bin/bash
# SYNOPSIS: One-click network repair for macOS: flush DNS, renew DHCP, toggle Wi-Fi, clear ARP.
# DRY-RUN BY DEFAULT. Needs sudo for DNS flush + ARP. Pair with network_diagnostics.sh to confirm.
# USAGE: bash repair_network.sh            (preview)
#        sudo bash repair_network.sh --force
#        options: --renew-only (skip the Wi-Fi power toggle)

FORCE=0; RENEW_ONLY=0
for a in "$@"; do case "$a" in --force) FORCE=1;; --renew-only) RENEW_ONLY=1;; esac; done
MODE="DRY RUN (add --force to apply)"; [ "$FORCE" -eq 1 ] && MODE="EXECUTE"

echo "=== Network Repair (macOS) ==="
echo "Mode: $MODE  |  Host: $(hostname -s)"
[ "$FORCE" -eq 1 ] && [ "$(id -u)" -ne 0 ] && echo "Note: not running with sudo — DNS flush and ARP clear will be skipped (re-run with sudo for a full repair)."
echo ""

step(){ local desc="$1"; shift; if [ "$FORCE" -eq 1 ]; then "$@" >/dev/null 2>&1 && echo "  OK  : $desc" || echo "  [!] : $desc (failed)"; else echo "  WOULD $desc"; fi; }

# DNS cache (needs root)
if [ "$(id -u)" -eq 0 ] || [ "$FORCE" -eq 0 ]; then
  step "flush DNS cache (dscacheutil)" dscacheutil -flushcache
  step "restart mDNSResponder" killall -HUP mDNSResponder
else
  echo "  skip  flush DNS / mDNSResponder (needs sudo)"
fi

# Active network service + interface
WIFI_IF=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi|AirPort/{getline; print $2; exit}')
ACTIVE_IF=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
echo "  (active interface: ${ACTIVE_IF:-unknown}; Wi-Fi: ${WIFI_IF:-none})"

# Renew DHCP on the active interface
if [ -n "$ACTIVE_IF" ]; then
  step "renew DHCP lease on $ACTIVE_IF" ipconfig set "$ACTIVE_IF" DHCP
fi

# Clear ARP cache (needs root)
if [ "$(id -u)" -eq 0 ]; then step "clear ARP cache" arp -a -d
elif [ "$FORCE" -eq 0 ]; then echo "  WOULD clear ARP cache (needs sudo)"; fi

# Toggle Wi-Fi power
if [ "$RENEW_ONLY" -eq 0 ] && [ -n "$WIFI_IF" ]; then
  if [ "$FORCE" -eq 1 ]; then
    echo "  Cycling Wi-Fi ($WIFI_IF) off/on..."
    networksetup -setairportpower "$WIFI_IF" off 2>/dev/null; sleep 3; networksetup -setairportpower "$WIFI_IF" on 2>/dev/null
    echo "  OK  : Wi-Fi power cycled"
  else
    echo "  WOULD cycle Wi-Fi power off/on ($WIFI_IF)"
  fi
fi

echo ""
if [ "$FORCE" -eq 1 ]; then echo "Done. Verify with network_diagnostics.sh."
else echo "Dry run complete. Re-run with sudo and --force. Use --renew-only to skip the Wi-Fi toggle."; fi
