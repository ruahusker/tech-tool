<#
.SYNOPSIS
    BitLocker encryption status + recovery keys for every volume. Read-only.
    Recovery passwords require an elevated session.
.DESCRIPTION
    The go-to before a reimage, a board swap, or when a user is locked out: shows each
    volume's encryption state, protection status, key protector types, and (when elevated)
    the 48-digit numeric recovery password and its key ID so you can match it to what's
    escrowed in AD/Entra/Intune. Also reports TPM readiness.
.PARAMETER OutFile
    Also save the report to a text file (handy for stashing the recovery key somewhere safe).
#>
[CmdletBinding()]
param([string]$OutFile)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$out = [System.Collections.Generic.List[string]]::new()
function W($s){ $out.Add($s) | Out-Null; Write-Output $s }

W "=== Disk Encryption (BitLocker) ==="
W ("Host: {0}  |  Elevated: {1}" -f $env:COMPUTERNAME, $isAdmin)
if (-not $isAdmin) { W "[!] Not elevated - recovery passwords will be hidden. Re-run as admin to retrieve keys." }
W ""

$haveCmdlets = $true
$vols = $null
try { $vols = Get-BitLockerVolume -ErrorAction Stop } catch { $haveCmdlets = $false }

if ($haveCmdlets) {
    foreach ($v in $vols) {
        W ("Volume {0}  [{1}]" -f $v.MountPoint, $v.VolumeType)
        W ("  Status        : {0} ({1}% encrypted)" -f $v.VolumeStatus, $v.EncryptionPercentage)
        W ("  Protection    : {0}" -f $v.ProtectionStatus)
        W ("  Method        : {0}" -f $v.EncryptionMethod)
        if ($v.VolumeStatus -eq 'FullyDecrypted' -and $v.MountPoint -eq $env:SystemDrive) { W "  [!] System drive is NOT encrypted." }
        if ($v.ProtectionStatus -eq 'Off' -and $v.VolumeStatus -ne 'FullyDecrypted') { W "  [!] Encrypted but protection is SUSPENDED (resumes on reboot, or run Resume-BitLocker)." }
        if ($v.KeyProtector) {
            W "  Key protectors:"
            foreach ($kp in $v.KeyProtector) {
                W ("    - {0}" -f $kp.KeyProtectorType)
                if ($kp.KeyProtectorType -eq 'RecoveryPassword') {
                    if ($isAdmin -and $kp.RecoveryPassword) {
                        W ("      Key ID  : {0}" -f $kp.KeyProtectorId)
                        W ("      RECOVERY: {0}" -f $kp.RecoveryPassword)
                    } else {
                        W ("      Key ID  : {0} (password hidden - needs elevation)" -f $kp.KeyProtectorId)
                    }
                }
            }
        } else {
            W "  Key protectors: none"
        }
        W ""
    }
} else {
    W "Get-BitLockerVolume unavailable on this SKU - falling back to manage-bde."
    W ""
    & manage-bde -status 2>$null | ForEach-Object { W "  $_" }
    if ($isAdmin) {
        W ""
        W ("Recovery protectors for {0}:" -f $env:SystemDrive)
        & manage-bde -protectors -get $env:SystemDrive 2>$null | ForEach-Object { W "  $_" }
    }
}

W "=== TPM ==="
try { $t = Get-Tpm -ErrorAction Stop; W ("  Present={0}  Ready={1}  Enabled={2}" -f $t.TpmPresent, $t.TpmReady, $t.TpmEnabled) }
catch { W "  TPM query needs elevation or is unavailable." }

if (-not $isAdmin) { W ""; W "[!] To capture recovery keys, re-run this tool elevated." }

if ($OutFile) {
    try { ($out -join "`r`n") | Out-File -FilePath $OutFile -Encoding UTF8; Write-Output ("`nSaved to {0}" -f $OutFile) }
    catch { Write-Output ("`n[!] Could not save to {0}: {1}" -f $OutFile, $_.Exception.Message) }
}
