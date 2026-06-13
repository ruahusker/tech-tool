#!/bin/bash
# SYNOPSIS: Directory binding (AD), Kerberos tickets, and time sync health. Read-only by default.
# --repair renews the Kerberos ticket and resyncs time (needs sudo for the resync).
# Most Macs are MDM-managed (not AD-bound); Kerberos + time still affect SSO/login.
# USAGE: bash domain_health.sh            (or: sudo bash domain_health.sh --repair)

REPAIR=0; for a in "$@"; do [ "$a" = "--repair" ] && REPAIR=1; done

echo "=== Domain / Directory Health (macOS) ==="
echo "Host: $(hostname -s)"

echo ""
echo "=== Directory Binding (Active Directory) ==="
AD=$(dsconfigad -show 2>/dev/null)
if [ -n "$AD" ]; then
  echo "$AD" | sed 's/^/  /'
else
  echo "  Not bound to Active Directory (typical for MDM-managed Macs)."
fi
echo "  Directory search nodes:"
dscl localhost -list / 2>/dev/null | grep -vE "^(Search|Contact|Local)$" | sed 's/^/    /'

echo ""
echo "=== Kerberos Tickets (klist) ==="
if klist 2>/dev/null | grep -qE "krbtgt|Principal"; then
  klist 2>/dev/null | sed 's/^/  /'
else
  echo "  No Kerberos tickets (normal unless using Enterprise SSO / AD login)."
fi

echo ""
echo "=== Time Sync ==="
echo "  Local time : $(date)"
if [ "$(id -u)" -eq 0 ]; then
  TSRV=$(systemsetup -getnetworktimeserver 2>/dev/null | sed 's/.*: //')
  USINGNT=$(systemsetup -getusingnetworktime 2>/dev/null | sed 's/.*: //')
  echo "  Time server: ${TSRV:-unknown}"
  echo "  Network time on: ${USINGNT:-unknown}"
else
  TSRV=$(awk '/^server/{print $2; exit}' /etc/ntp.conf 2>/dev/null)
  echo "  Time server: ${TSRV:-(needs sudo to confirm)}"
  echo "  Network time on: (needs sudo to read)"
fi
if [ -n "$TSRV" ] && [ "$TSRV" != "unknown" ]; then
  OFFSET=$(sntp "$TSRV" 2>/dev/null | grep -oE '[+-][0-9]+\.[0-9]+' | head -1)
  [ -n "$OFFSET" ] && echo "  Offset vs server: ${OFFSET}s"
fi
echo "  [i] Clock skew over ~5 min breaks Kerberos/AD logins and SSO."

if [ "$REPAIR" -eq 1 ]; then
  echo ""
  echo "=== Repair: renew Kerberos + resync time ==="
  [ "$(id -u)" -ne 0 ] && echo "  [!] --repair needs sudo for the time resync; doing what is possible."
  kinit -R 2>/dev/null && echo "  OK  : Kerberos ticket renewed" || echo "  --  : no renewable ticket (or no AD login)"
  if [ "$(id -u)" -eq 0 ]; then
    sntp -sS "${TSRV:-time.apple.com}" 2>/dev/null && echo "  OK  : time resynced against ${TSRV:-time.apple.com}" || echo "  [!] : time resync failed"
  fi
  echo "  Done."
else
  echo ""
  echo "Read-only. Add --repair (with sudo) to renew Kerberos and resync the clock."
fi
