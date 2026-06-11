<#
.SYNOPSIS
    Security posture snapshot: AV, firewall, BitLocker, UAC, local admins, RDP, SMBv1.
.DESCRIPTION
    Read-only. Run during any visit to spot obvious exposure. Some checks degrade
    gracefully without admin (noted inline).
#>
[CmdletBinding()]
param()

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Output ("Running elevated: {0}`n" -f $isAdmin)

Write-Output "=== ANTIVIRUS ==="
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    Write-Output ("  Defender: RealTime={0}  Definitions={1} (age {2}d)  LastQuickScan={3}" -f `
        $mp.RealTimeProtectionEnabled, $mp.AntivirusSignatureVersion, $mp.AntivirusSignatureAge, $mp.QuickScanEndTime)
    if (-not $mp.RealTimeProtectionEnabled) { Write-Output "  [!] Real-time protection OFF" }
    if ($mp.AntivirusSignatureAge -gt 7) { Write-Output "  [!] Definitions older than 7 days" }
} catch { Write-Output "  Defender module unavailable (third-party AV may be primary)." }
try {
    Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object {
        $state = '{0:X6}' -f $_.productState
        $enabled = $state.Substring(2,2) -in '10','11'
        $updated = $state.Substring(4,2) -eq '00'
        Write-Output ("  Registered AV: {0}  Enabled={1}  UpToDate={2}" -f $_.displayName, $enabled, $updated)
    }
} catch { Write-Output "  (SecurityCenter2 not available - server SKU?)" }

Write-Output "`n=== FIREWALL ==="
Get-NetFirewallProfile | ForEach-Object {
    $flag = if (-not $_.Enabled) { "  [!] OFF" } else { "" }
    Write-Output ("  {0,-9} Enabled={1}{2}" -f $_.Name, $_.Enabled, $flag)
}

Write-Output "`n=== DISK ENCRYPTION (BitLocker) ==="
if ($isAdmin) {
    try {
        Get-BitLockerVolume -ErrorAction Stop | ForEach-Object {
            $flag = if ($_.VolumeStatus -eq 'FullyDecrypted' -and $_.MountPoint -eq $env:SystemDrive) { "  [!] system drive unencrypted" } else { "" }
            Write-Output ("  {0}  {1}  {2}% encrypted  Protection={3}{4}" -f $_.MountPoint, $_.VolumeStatus, $_.EncryptionPercentage, $_.ProtectionStatus, $flag)
        }
    } catch { Write-Output "  BitLocker cmdlets unavailable on this SKU." }
} else { Write-Output "  (requires elevation)" }

Write-Output "`n=== UAC ==="
$uac = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue
Write-Output ("  EnableLUA={0}  ConsentPromptBehaviorAdmin={1}" -f $uac.EnableLUA, $uac.ConsentPromptBehaviorAdmin)
if ($uac.EnableLUA -eq 0) { Write-Output "  [!] UAC disabled" }

Write-Output "`n=== LOCAL ADMINISTRATORS ==="
try {
    Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop | ForEach-Object {
        Write-Output ("  {0,-10} {1}" -f $_.ObjectClass, $_.Name)
    }
} catch {
    # Get-LocalGroupMember chokes on orphaned domain SIDs; fall back to net.exe
    & net localgroup Administrators 2>$null | Select-Object -Skip 6 | Where-Object { $_ -and $_ -notmatch 'command completed' } | ForEach-Object { Write-Output "  $_" }
}

Write-Output "`n=== REMOTE ACCESS ==="
$rdp = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -ErrorAction SilentlyContinue).fDenyTSConnections
Write-Output ("  RDP enabled : {0}" -f ($rdp -eq 0))
$winrm = Get-Service WinRM -ErrorAction SilentlyContinue
Write-Output ("  WinRM       : {0}" -f $winrm.Status)

Write-Output "`n=== LEGACY PROTOCOLS ==="
$smb1 = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name SMB1 -ErrorAction SilentlyContinue).SMB1
if ($smb1 -eq 1) { Write-Output "  [!] SMBv1 server explicitly ENABLED (WannaCry-era protocol - should be off)" }
else {
    $feat = if ($isAdmin) { (Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue).State } else { "unknown (needs elevation)" }
    Write-Output "  SMBv1 feature state: $feat"
}

Write-Output "`n=== SECURE BOOT / TPM ==="
try { Write-Output ("  SecureBoot : {0}" -f (Confirm-SecureBootUEFI -ErrorAction Stop)) } catch { Write-Output "  SecureBoot : unavailable ($($_.Exception.Message.Split("`n")[0]))" }
try { $tpm = Get-Tpm -ErrorAction Stop; Write-Output ("  TPM        : Present={0} Ready={1}" -f $tpm.TpmPresent, $tpm.TpmReady) } catch { Write-Output "  TPM        : query needs elevation" }
