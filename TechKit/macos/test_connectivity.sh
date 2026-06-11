#!/bin/bash
# SYNOPSIS: Targeted connectivity test to one host: DNS, ping, TCP port, optional traceroute.
# Read-only. Usage: bash test_connectivity.sh <host> [port] [--trace]
# EXAMPLE: bash test_connectivity.sh fileserver01 445

TARGET="$1"; PORT="$2"
if [ -z "$TARGET" ]; then echo "Usage: bash test_connectivity.sh <host> [port] [--trace]"; exit 1; fi
[ "$PORT" = "--trace" ] && { PORT=""; TRACE=1; }
[ "$3" = "--trace" ] && TRACE=1

echo "=== DNS RESOLUTION: $TARGET ==="
if echo "$TARGET" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
    echo "  (IP literal, skipping DNS)"
else
    IPS=$(dscacheutil -q host -a name "$TARGET" 2>/dev/null | awk '/ip_address/{print $2}')
    if [ -n "$IPS" ]; then echo "  Resolves to: $(echo $IPS | tr '\n' ' ')"
    else
        echo "  [!] System resolver FAILED for $TARGET"
        DIG=$(dig +short "$TARGET" 2>/dev/null | head -3)
        if [ -n "$DIG" ]; then echo "  ...but direct DNS query works: $(echo $DIG | tr '\n' ' ') -> local resolver/scoped-DNS issue (VPN?)"
        else echo "  Direct DNS query also failed. If IP works, fix DNS; if not, host may not exist."; fi
    fi
fi

echo ""
echo "=== PING ==="
PING=$(ping -c 4 -t 8 "$TARGET" 2>&1 | tail -2)
if echo "$PING" | grep -q "packets received"; then  # bash 3.2-safe; macOS says 'packets received'
    echo "$PING" | sed 's/^/  /'
else
    echo "  No reply (note: ICMP is often blocked - not conclusive alone)."
fi

if [ -n "$PORT" ]; then
    echo ""
    echo "=== TCP PORT $PORT ==="
    if nc -z -G 5 "$TARGET" "$PORT" 2>/dev/null; then
        echo "  OPEN - service reachable on $TARGET:$PORT"
    else
        echo "  [!] CLOSED/FILTERED - no TCP connect within 5s."
        echo "  If ping works but port fails: service down or a firewall blocks that port."
    fi
fi

if [ -n "$TRACE" ]; then
    echo ""
    echo "=== TRACEROUTE ==="
    traceroute -n -m 20 -w 1 "$TARGET" 2>&1 | sed 's/^/  /'
fi

echo ""
echo "Common ports: 80/443 web, 445 SMB, 3389 RDP, 22 SSH, 548 AFP, 5900 screen sharing, 9100 printing"
