<#
.SYNOPSIS
    Disable (or delete) local user accounts inactive for N days. DRY-RUN BY DEFAULT.
.DESCRIPTION
    DESTRUCTIVE - requires admin. Without -Force it only reports what it WOULD do.
    Safety rails:
      - Default action is DISABLE, not delete. Deleting requires -Delete explicitly.
      - Members of the local Administrators group are NEVER touched. No override exists.
      - Built-in accounts and the current user are never touched.
      - Accounts that have never logged on are skipped unless -IncludeNeverLoggedOn.
      - Local accounts only; domain accounts are not in scope of Get-LocalUser.
      - Every action is appended to a log file next to the script's collections folder.
.PARAMETER DaysInactive
    Inactivity threshold in days (default 90).
.PARAMETER Delete
    Delete accounts instead of disabling them. This ALSO removes each deleted
    user's C:\Users profile folder (where the disk space actually is) and the
    registry hive, then reports how much was freed. Use -KeepProfile to delete
    the account but leave its profile on disk.
.PARAMETER KeepProfile
    With -Delete: keep the user's C:\Users profile folder instead of reclaiming
    it. The account is removed but no disk space is freed.
.PARAMETER RemoveProfile
    Deprecated / no-op: profile removal is the default with -Delete now. Kept so
    older command lines keep working.
.PARAMETER IncludeNeverLoggedOn
    Also act on accounts with no recorded logon (off by default - these are often service accounts).
.PARAMETER Exclude
    Additional account names to protect, e.g. -Exclude svc_backup,kiosk
.PARAMETER Force
    Actually perform the actions. Without this, dry-run only.
.EXAMPLE
    .\Remove-InactiveUsers.ps1 -DaysInactive 90                  # dry run: show candidates + reclaimable space
    .\Remove-InactiveUsers.ps1 -DaysInactive 90 -Force           # disable them (reversible, frees no space)
    .\Remove-InactiveUsers.ps1 -DaysInactive 180 -Delete -Force  # delete + remove profiles, reclaim disk
    .\Remove-InactiveUsers.ps1 -DaysInactive 180 -Delete -KeepProfile -Force  # delete accounts, keep profiles
#>
[CmdletBinding()]
param(
    [int]$DaysInactive = 90,
    [switch]$Delete,
    [switch]$KeepProfile,
    [switch]$RemoveProfile,   # deprecated: profile removal is the default with -Delete now
    [switch]$IncludeNeverLoggedOn,
    [string[]]$Exclude = @(),
    [switch]$Force
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Force -and -not $isAdmin) { Write-Output "[!] -Force requires an elevated PowerShell. Aborting."; exit 1 }

# Deleting an account only reclaims disk space if its profile folder is removed.
# That is the default with -Delete; -KeepProfile opts out.
$removeProfiles = $Delete -and -not $KeepProfile

# Junction-safe folder size in bytes. Skips reparse points so the legacy AppData
# junctions inside a profile are not double-counted and cannot cause loops.
function Get-FolderSize($folderPath) {
    if (-not $folderPath -or -not (Test-Path -LiteralPath $folderPath)) { return [int64]0 }
    $total = [int64]0
    $stack = New-Object System.Collections.Stack
    $stack.Push($folderPath)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try {
            foreach ($f in [System.IO.Directory]::EnumerateFiles($dir)) {
                try { $total += (New-Object System.IO.FileInfo $f).Length } catch {}
            }
            foreach ($d in [System.IO.Directory]::EnumerateDirectories($dir)) {
                try {
                    if ([System.IO.File]::GetAttributes($d) -band [System.IO.FileAttributes]::ReparsePoint) { continue }
                } catch { continue }
                $stack.Push($d)
            }
        } catch {}
    }
    return $total
}

function Format-Size([int64]$bytes) {
    if ($bytes -ge 1GB) { return ("{0:N1} GB" -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ("{0:N1} MB" -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ("{0:N0} KB" -f ($bytes / 1KB)) }
    return ("{0} B" -f $bytes)
}

# Resolve a local user's on-disk profile. Match by SID (robust - works even when
# the folder is not named after the user, e.g. john.DOMAIN), fall back to path.
function Get-UserProfile($user) {
    $sid = $null
    try { $sid = $user.SID.Value } catch {}
    $p = $null
    if ($sid) {
        $p = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { $_.SID -eq $sid } | Select-Object -First 1
    }
    if (-not $p) {
        $p = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { -not $_.Special -and $_.LocalPath -like "*\$($user.Name)" } | Select-Object -First 1
    }
    return $p
}

$builtin = @('Administrator','DefaultAccount','Guest','WDAGUtilityAccount','defaultuser0')
$cutoff  = (Get-Date).AddDays(-$DaysInactive)
$action  = if ($Delete) { "DELETE" } else { "DISABLE" }
$mode    = if ($Force) { "EXECUTE" } else { "DRY RUN (no changes will be made; add -Force to apply)" }

$adminMembers = @()
try { $adminMembers = (Get-LocalGroupMember Administrators -ErrorAction Stop).Name | ForEach-Object { ($_ -split '\\')[-1] } } catch {}

Write-Output "Mode: $mode"
Write-Output "Action for matches: $action  |  Threshold: no logon since $($cutoff.ToString('yyyy-MM-dd'))  |  Host: $env:COMPUTERNAME`n"

$candidates = @(); $skipped = @()
foreach ($u in Get-LocalUser) {
    $why = $null
    if ($builtin -contains $u.Name)                  { $why = "built-in account" }
    elseif ($u.Name -ieq $env:USERNAME)              { $why = "current user" }
    elseif ($Exclude -contains $u.Name)              { $why = "excluded by -Exclude" }
    elseif ($adminMembers -contains $u.Name) { $why = "Administrators member (admin accounts are never touched)" }
    elseif (-not $u.LastLogon -and -not $IncludeNeverLoggedOn)        { $why = "never logged on (use -IncludeNeverLoggedOn to override)" }
    elseif ($u.LastLogon -and $u.LastLogon -gt $cutoff)               { $why = "active (last logon $($u.LastLogon.ToString('yyyy-MM-dd')))" }
    elseif (-not $u.Enabled -and -not $Delete)                        { $why = "already disabled" }

    if ($why) { $skipped += "  SKIP  {0,-22} {1}" -f $u.Name, $why }
    else      { $candidates += $u }
}

Write-Output "=== PROTECTED / SKIPPED ==="
$skipped | ForEach-Object { Write-Output $_ }

Write-Output "`n=== CANDIDATES ($($candidates.Count)) ==="
if (-not $candidates) { Write-Output "  None. Nothing to do."; exit 0 }

$logFile = Join-Path $PSScriptRoot ("..\collections\{0}-user-cleanup-{1}.log" -f $env:COMPUTERNAME, (Get-Date -Format "yyyyMMdd-HHmmss"))
function Log($msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Write-Output "  $msg"
    if ($Force) { try { Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue } catch {} }
}

$totalFreed     = [int64]0   # bytes actually reclaimed (apply)
$totalPotential = [int64]0   # bytes that would be reclaimed (dry run)

foreach ($u in $candidates) {
    $last = if ($u.LastLogon) { $u.LastLogon.ToString('yyyy-MM-dd') } else { "never" }

    # Resolve + size the profile up front so we can report it (only when deleting).
    $prof = $null; $profPath = $null; $profLoaded = $false; $profSize = [int64]0
    if ($Delete) {
        $prof = Get-UserProfile $u
        if ($prof) {
            $profPath   = $prof.LocalPath
            $profLoaded = [bool]$prof.Loaded
            $profSize   = Get-FolderSize $profPath
        }
    }

    if (-not $Force) {
        # ---- DRY RUN ----
        if (-not $Delete) {
            Write-Output ("  WOULD DISABLE {0,-22} (last logon {1}) - reversible, frees no space" -f $u.Name, $last)
        } elseif ($removeProfiles -and $prof -and $profLoaded) {
            Write-Output ("  [!] WOULD DELETE {0,-20} (last logon {1}) - profile is LOADED (in use); {2} cannot be reclaimed until that user is logged off" -f $u.Name, $last, (Format-Size $profSize))
        } elseif ($removeProfiles -and $prof) {
            $totalPotential += $profSize
            Write-Output ("  WOULD DELETE {0,-22} (last logon {1}) - frees {2}  [{3}]" -f $u.Name, $last, (Format-Size $profSize), $profPath)
        } elseif ($removeProfiles) {
            Write-Output ("  WOULD DELETE {0,-22} (last logon {1}) - no profile on disk (frees nothing)" -f $u.Name, $last)
        } else {
            $keep = if ($profPath) { " - profile KEPT at $profPath ($(Format-Size $profSize))" } else { "" }
            Write-Output ("  WOULD DELETE {0,-22} (last logon {1}){2}" -f $u.Name, $last, $keep)
        }
        continue
    }

    # ---- EXECUTE ----
    try {
        if ($Delete) {
            Remove-LocalUser -Name $u.Name -ErrorAction Stop
            if (-not $removeProfiles) {
                $kept = if ($profPath) { " (profile KEPT at $profPath, $(Format-Size $profSize))" } else { "" }
                Log ("DELETED user {0}{1}" -f $u.Name, $kept)
            } elseif (-not $prof) {
                Log ("DELETED user {0} (no profile on disk to reclaim)" -f $u.Name)
            } elseif ($profLoaded) {
                Log ("[!] DELETED user {0}; profile {1} is LOADED (in use) - NOT removed, {2} not reclaimed" -f $u.Name, $profPath, (Format-Size $profSize))
            } else {
                $removed = $false
                try { $prof | Remove-CimInstance -ErrorAction Stop; $removed = $true }
                catch {
                    # CIM/registry removal failed (often a locked handle); delete the folder directly.
                    try { Remove-Item -LiteralPath $profPath -Recurse -Force -ErrorAction Stop; $removed = $true }
                    catch { Log ("[!] DELETED user {0}; FAILED to remove profile {1}: {2}" -f $u.Name, $profPath, $_.Exception.Message) }
                }
                if ($removed) {
                    $totalFreed += $profSize
                    Log ("DELETED user {0} + profile {1} (freed {2})" -f $u.Name, $profPath, (Format-Size $profSize))
                }
            }
        } else {
            Disable-LocalUser -Name $u.Name -ErrorAction Stop
            Log ("DISABLED user {0} (last logon {1})" -f $u.Name, $last)
        }
    } catch {
        Log ("FAILED on {0}: {1}" -f $u.Name, $_.Exception.Message)
    }
}

if ($Force) {
    if ($removeProfiles) { Write-Output ("`nTOTAL DISK RECLAIMED: {0}" -f (Format-Size $totalFreed)) }
    Write-Output "Action log: $logFile"
} else {
    if ($removeProfiles) { Write-Output ("`nTOTAL RECLAIMABLE: {0} (re-run with -Force to apply)" -f (Format-Size $totalPotential)) }
    Write-Output "`nDry run complete. Re-run with -Force to apply the $action actions above."
}
Write-Output "Tip: DISABLE is reversible (Enable-LocalUser) but frees no space. DELETE reclaims disk by removing the profile (default); add -KeepProfile to keep it."
if ($Delete) { Write-Output "Note: if Windows still shows the space as used afterward, System Protection / shadow copies (VSS) may be holding the freed data - Windows purges that only when space is needed. Check with: vssadmin list shadowstorage" }
