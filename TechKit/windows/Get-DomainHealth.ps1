<#
.SYNOPSIS
    Active Directory domain & Group Policy health: secure channel, DC, Kerberos, time sync,
    and Group Policy application. Read-only by default; -Repair forces a GP update + time resync.
.DESCRIPTION
    For "can't log in", "GPO/drive maps not applying", "computer fell off the domain", and
    Kerberos/time-skew auth failures. Checks the machine secure channel to the domain, locates
    a domain controller, lists Kerberos tickets, reports the time source, and summarizes which
    GPOs applied. -Repair runs gpupdate /force and w32tm /resync (safe, but talks to the DC).
.PARAMETER Repair
    Force a Group Policy refresh (gpupdate /force) and a time resync (w32tm /resync).
#>
[CmdletBinding()]
param([switch]$Repair)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$cs = Get-CimInstance Win32_ComputerSystem
Write-Output "=== Domain & Group Policy Health ==="
Write-Output ("Host: {0}  |  Elevated: {1}" -f $env:COMPUTERNAME, $isAdmin)

if (-not $cs.PartOfDomain) {
    Write-Output ("[!] This machine is NOT domain-joined (workgroup: {0}). Domain checks skipped." -f $cs.Workgroup)
    Write-Output ("    Logon server: {0}" -f $env:LOGONSERVER)
} else {
    Write-Output ("Domain        : {0}" -f $cs.Domain)
    Write-Output ("Logon server  : {0}" -f $env:LOGONSERVER)

    Write-Output "`n=== Secure Channel ==="
    try {
        $sc = Test-ComputerSecureChannel -ErrorAction Stop
        if ($sc) { Write-Output "  OK  : secure channel to the domain is healthy." }
        else { Write-Output "  [!] Secure channel BROKEN - machine trust is bad. Fix: Test-ComputerSecureChannel -Repair (needs domain creds) or rejoin." }
    } catch { Write-Output ("  [!] Secure channel test failed: {0}" -f $_.Exception.Message) }

    Write-Output "`n=== Domain Controller ==="
    & nltest "/dsgetdc:$($cs.Domain)" 2>$null | Where-Object { $_ -match 'DC:|Address:|Dom Name:|Forest|Flags' } | ForEach-Object { Write-Output ("  {0}" -f $_.Trim()) }

    Write-Output "`n=== Kerberos Tickets (klist) ==="
    $kl = & klist 2>$null
    if ($kl | Where-Object { $_ -match 'krbtgt' }) { Write-Output "  TGT present." } else { Write-Output "  [!] No krbtgt ticket found - Kerberos may not be working (check time/DNS)." }
    ($kl | Select-Object -First 4) | ForEach-Object { Write-Output ("  {0}" -f $_) }
}

Write-Output "`n=== Time Sync ==="
$st = & w32tm /query /status 2>$null
if ($st) { $st | Where-Object { $_ -match 'Source|Last Successful|Stratum|Leap' } | ForEach-Object { Write-Output ("  {0}" -f $_.Trim()) } }
else { Write-Output "  w32tm status unavailable." }
& w32tm /query /source 2>$null | ForEach-Object { Write-Output ("  Source: {0}" -f $_) }

Write-Output "`n=== Group Policy (gpresult /scope:computer) ==="
$gp = & gpresult /r /scope:computer 2>$null
if ($gp) {
    $gp | Where-Object { $_ -match 'Last time Group Policy was applied|Group Policy was applied from|Domain Name|Site Name' } | ForEach-Object { Write-Output ("  {0}" -f $_.Trim()) }
    $applied = $false
    foreach ($l in $gp) {
        if ($l -match 'Applied Group Policy Objects') { Write-Output "  Applied GPOs:"; $applied = $true; continue }
        if ($applied) {
            if ([string]::IsNullOrWhiteSpace($l)) { break }
            if ($l -notmatch '----') { Write-Output ("    - {0}" -f $l.Trim()) }
        }
    }
} else { Write-Output "  gpresult unavailable (try elevated)." }

if ($Repair) {
    Write-Output "`n=== Repair: forcing GP update + time resync ==="
    if (-not $isAdmin) { Write-Output "  [!] -Repair works best elevated; continuing anyway." }
    Write-Output "  Running gpupdate /force ..."
    & gpupdate /force 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Output ("    {0}" -f $_) }
    Write-Output "  Running w32tm /resync ..."
    & w32tm /resync /force 2>&1 | ForEach-Object { Write-Output ("    {0}" -f $_) }
    Write-Output "  Done."
} else {
    Write-Output "`nRead-only. Add -Repair to force a Group Policy refresh and time resync."
}
