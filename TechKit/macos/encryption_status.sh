#!/bin/bash
# SYNOPSIS: FileVault encryption status, enabled users, and recovery-key posture. Read-only.
# Needs sudo for full detail (enabled users, recovery-key type). Degrades gracefully.
# USAGE: bash encryption_status.sh   (or: sudo bash encryption_status.sh for full detail)

echo "=== Disk Encryption (FileVault) ==="
echo "Host: $(hostname -s)"
SUDO=0; [ "$(id -u)" -eq 0 ] && SUDO=1
[ "$SUDO" -eq 0 ] && echo "[!] Not running with sudo - enabled-user list and recovery-key detail will be limited."
echo ""

STATUS=$(fdesetup status 2>/dev/null)
echo "$STATUS" | sed 's/^/  /'
echo "$STATUS" | grep -qi "FileVault is Off" && echo "  [!] FileVault is OFF - this disk is unencrypted. A lost/stolen Mac = readable data."
echo "$STATUS" | grep -qi "in progress"      && echo "  [~] Encryption still in progress - do not assume the disk is protected yet."

if [ "$SUDO" -eq 1 ]; then
  echo ""
  echo "=== Enabled (Unlock) Users ==="
  fdesetup list 2>/dev/null | sed 's/^/  /' || echo "  (none / unavailable)"

  echo ""
  echo "=== Recovery Key Posture ==="
  if fdesetup haspersonalrecoverykey 2>/dev/null | grep -qi true; then
    echo "  Personal recovery key: PRESENT (the 24-char key shown when FileVault was enabled)."
    echo "  [i] macOS never re-displays it. If it was not recorded, regenerate: sudo fdesetup changerecovery -personal"
  else
    echo "  Personal recovery key: none"
  fi
  if fdesetup hasinstitutionalrecoverykey 2>/dev/null | grep -qi true; then
    echo "  Institutional recovery key: PRESENT (FileVaultMaster keychain - org escrow)."
  else
    echo "  Institutional recovery key: none"
  fi
  echo "  [i] In a managed fleet the personal key is usually escrowed to MDM (Jamf/Intune) - recover it there."
fi

echo ""
echo "=== Volume Encryption (APFS) ==="
diskutil apfs list 2>/dev/null | grep -E "APFS Volume Disk|FileVault|Encrypted|Name:" | sed 's/^/  /' | head -40

echo ""
echo "=== Hardware Security Context ==="
HW=$(system_profiler SPiBridgeDataType 2>/dev/null | grep -i "Model Name" | head -1 | sed 's/.*: //')
[ -n "$HW" ] && echo "  Secure chip: $HW"
ALT=$(system_profiler SPHardwareDataType 2>/dev/null | grep -i "Activation Lock Status" | sed 's/.*: //')
[ -n "$ALT" ] && echo "  Activation Lock: $ALT"
echo "  [i] On Apple silicon/T2 the data volume is hardware-encrypted even before FileVault; FileVault adds the at-boot password requirement."
