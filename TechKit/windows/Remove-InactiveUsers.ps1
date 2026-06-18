<#
.SYNOPSIS
    Reclaim disk space by removing stale user PROFILES (local AND domain). DRY-RUN BY DEFAULT.
.DESCRIPTION
    DESTRUCTIVE - requires admin to apply. Without -Force it only reports what it WOULD remove.

    Works on domain-joined machines: it enumerates Win32_UserProfile (which includes domain
    users on the box), not just local accounts, and decides "inactive" by each profile's
    LastUseTime. Removing a profile deletes that user's C:\Users folder + registry entry to
    reclaim space; the underlying account is left intact (a domain/AD account cannot and should
    not be managed from a member PC) unless -Delete is given for a LOCAL account.

    Safety rails:
      - DRY RUN unless -Force.
      - Loaded (currently logged-on / in-use) profiles are never removed.
      - The current user and members of the local Administrators group are never touched.
      - Special / system profiles (Default, Public, service accounts) are never touched.
      - Orphaned profiles (SID no longer resolves to an account) are skipped unless -IncludeOrphaned.
      - Every action is appended to a log file in the TechKit collections folder.
      - Always review the dry-run list (it shows names) before applying; protect anyone with -Exclude.
.PARAMETER DaysInactive
    Inactivity threshold in days (default 90), measured by profile LastUseTime. Always treated
    as a positive number, so it can never produce a future cutoff. Ignored when -All is set.
.PARAMETER All
    Target EVERY profile except the protected ones (the current user, members of the local
    Administrators group, in-use/loaded profiles, system profiles, and -Exclude names),
    ignoring LastUseTime entirely. Use to clear a machine - e.g. before reimaging, or when the
    last-use timestamps are unreliable (Windows bumps them for background/service activity, not
    just real logons). Still dry-run unless -Force. Includes orphaned profiles automatically.
.PARAMETER Delete
    For LOCAL accounts only: also delete the account object after removing its profile. Domain
    accounts cannot be deleted from a member machine, so for them only the local profile is removed.
    (Account deletion is OPT-IN: without -Delete, local accounts are kept - only the profile goes.)
.PARAMETER SkipLocalAccounts
    Leave LOCAL accounts entirely alone - skip their profiles too, so only domain (and, with
    -IncludeOrphaned, orphaned) profiles are reclaimed. Use on machines with intentional local
    accounts (kiosk, lab/tech) you never want touched.
.PARAMETER IncludeOrphaned
    Also remove profiles whose SID no longer resolves to an account (deleted local/AD user).
    These are often the biggest space wins, but the last user cannot be verified.
.PARAMETER Exclude
    Account names to protect, e.g. -Exclude svc_backup,kiosk (matches the name part, ignoring domain).
.PARAMETER Force
    Actually perform the removals. Without this, dry-run only.
.EXAMPLE
    .\Remove-InactiveUsers.ps1 -DaysInactive 90                       # dry run: stale profiles + reclaimable space
    .\Remove-InactiveUsers.ps1 -DaysInactive 90 -Force                # remove those profiles, reclaim disk
    .\Remove-InactiveUsers.ps1 -DaysInactive 180 -IncludeOrphaned -Force
    .\Remove-InactiveUsers.ps1 -DaysInactive 180 -Delete -Force       # also delete the LOCAL accounts
#>
[CmdletBinding()]
param(
    [int]$DaysInactive = 90,
    [switch]$All,
    [switch]$Delete,
    [switch]$SkipLocalAccounts,
    [switch]$IncludeOrphaned,
    [string[]]$Exclude = @(),
    [switch]$Force,
    # Deprecated / accepted-but-ignored so older command lines keep working:
    [switch]$KeepProfile,
    [switch]$RemoveProfile,
    [switch]$IncludeNeverLoggedOn
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Force -and -not $isAdmin) { Write-Output "[!] -Force requires an elevated PowerShell. Aborting."; exit 1 }

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

# Translate a SID string to DOMAIN\user (or MACHINE\user). $null = orphaned (account gone).
function Resolve-Sid($sidString) {
    try { return ([System.Security.Principal.SecurityIdentifier]$sidString).Translate([System.Security.Principal.NTAccount]).Value } catch { return $null }
}

# --- Threshold. Abs() + floor guarantee a past cutoff even if a negative/zero slips in. ---
$days = [math]::Abs($DaysInactive)
if ($days -lt 1) { $days = 90 }
$now    = Get-Date
$cutoff = $now.AddDays(-$days)

# --- Protection sets ---
$currentSid = ""
try { $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch {}
$excludeNames = @($Exclude | ForEach-Object { ($_ -split '\\')[-1] })

# Local Administrators members (direct). Note: members nested via a group (e.g. Domain Admins)
# are not expanded here - the dry-run list is the backstop, so review it before applying.
$adminSids = @(); $adminNames = @()
try {
    $m = Get-LocalGroupMember -Group Administrators -ErrorAction Stop
    $adminSids  = @($m | ForEach-Object { $_.SID.Value })
    $adminNames = @($m | ForEach-Object { ($_.Name -split '\\')[-1] })
} catch {
    try {
        $started = $false
        foreach ($line in (net localgroup Administrators 2>$null)) {
            if ($line -match '^----') { $started = $true; continue }
            if (-not $started) { continue }
            if ($line -match 'completed successfully') { break }
            $t = "$line".Trim()
            if ($t) { $adminNames += ($t -split '\\')[-1] }
        }
    } catch {}
}

$mode = if ($Force) { "EXECUTE" } else { "DRY RUN (no changes; add -Force to apply)" }
Write-Output "Mode: $mode"
Write-Output ("Now:    {0}" -f $now.ToString('yyyy-MM-dd HH:mm'))
if ($All) {
    Write-Output ("Scope:  ALL profiles except protected (current user, Administrators, in-use, system, -Exclude) - last-use IGNORED  |  Host: {0}`n" -f $env:COMPUTERNAME)
} else {
    Write-Output ("Cutoff: profiles not used since {0}  (idle more than {1} days)  |  Host: {2}`n" -f $cutoff.ToString('yyyy-MM-dd'), $days, $env:COMPUTERNAME)
}

# --- Enumerate profiles (this is what sees domain users; Get-LocalUser would not) ---
$profiles = @()
try { $profiles = @(Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object { -not $_.Special }) }
catch { Write-Output "[!] Could not enumerate user profiles: $($_.Exception.Message)"; exit 1 }

Write-Output "=== PROTECTED / SKIPPED ==="
$candidates = @()
foreach ($p in $profiles) {
    $sid  = [string]$p.SID
    $path = [string]$p.LocalPath
    if (-not $path) { continue }
    $loaded    = [bool]$p.Loaded
    $name      = Resolve-Sid $sid
    $shortName = if ($name) { ($name -split '\\')[-1] } else { $null }
    $display   = if ($name) { $name } else { "(orphaned: $sid)" }
    $lastUse   = $null
    if ($p.LastUseTime) { try { $lastUse = [datetime]$p.LastUseTime } catch {} }
    # A profile is "local" if its SID belongs to a local account (domain SIDs won't match).
    $isLocal = $false
    if ($name) { try { if (Get-LocalUser -SID ([System.Security.Principal.SecurityIdentifier]$sid) -ErrorAction Stop) { $isLocal = $true } } catch {} }

    $why = $null
    if ($loaded)                                                          { $why = "loaded - user is logged on / in use" }
    elseif ($sid -eq $currentSid)                                         { $why = "current user" }
    elseif (($adminSids -contains $sid) -or ($shortName -and $adminNames -contains $shortName)) { $why = "Administrators member (admin profiles are never touched)" }
    elseif ($shortName -and ($excludeNames -contains $shortName))         { $why = "excluded by -Exclude" }
    elseif ($isLocal -and $SkipLocalAccounts)                             { $why = "local account (-SkipLocalAccounts set)" }
    elseif (-not $All -and -not $name -and -not $IncludeOrphaned)         { $why = "orphaned (account deleted) - use -IncludeOrphaned or -All to reclaim" }
    elseif (-not $All -and $lastUse -and $lastUse -gt $cutoff)            { $why = "active (last used $($lastUse.ToString('yyyy-MM-dd'))) - use -All to override" }
    elseif (-not $All -and -not $lastUse -and -not $IncludeOrphaned)      { $why = "no last-use timestamp - use -IncludeOrphaned or -All to include" }

    if ($why) {
        Write-Output ("  SKIP  {0,-30} {1}" -f $display, $why)
    } else {
        $candidates += [pscustomobject]@{ Sid=$sid; Path=$path; Name=$name; Display=$display; LastUse=$lastUse; Orphaned=(-not $name); IsLocal=$isLocal; Size=[int64]0 }
    }
}

if (-not $candidates) {
    Write-Output "`n=== CANDIDATES (0) ===`n  None. No stale profiles match (everything is in use, recent, protected, or orphaned without -IncludeOrphaned)."
    exit 0
}

# Size each candidate (junction-safe), biggest first so the largest wins show at the top.
foreach ($c in $candidates) {
    $c.Size = Get-FolderSize $c.Path
}
$candidates = @($candidates | Sort-Object Size -Descending)

Write-Output ("`n=== CANDIDATES ({0}) ===" -f $candidates.Count)

$logFile = Join-Path $PSScriptRoot ("..\collections\{0}-profile-cleanup-{1}.log" -f $env:COMPUTERNAME, (Get-Date -Format "yyyyMMdd-HHmmss"))
function Log($msg) {
    Write-Output "  $msg"
    if ($Force) { try { Add-Content -Path $logFile -Value ("{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg) -ErrorAction SilentlyContinue } catch {} }
}

$totalFreed = [int64]0; $totalPotential = [int64]0
$total = $candidates.Count
$done  = 0
foreach ($c in $candidates) {
    $lastStr = if ($c.LastUse) { $c.LastUse.ToString('yyyy-MM-dd') } else { "unknown" }
    $tag = if ($c.Orphaned) { "[orphaned]" } elseif ($c.IsLocal) { "[local]" } else { "[domain]" }

    if (-not $Force) {
        # ---- DRY RUN ----
        $totalPotential += $c.Size
        $extra = if ($Delete -and $c.IsLocal) { " (+ delete local account)" } else { "" }
        Write-Output ("  WOULD RECLAIM {0,-30} {1,-10} last used {2}  frees {3}{4}  [{5}]" -f $c.Display, $tag, $lastStr, (Format-Size $c.Size), $extra, $c.Path)
        continue
    }

    # ---- EXECUTE: remove the profile (folder + registry) ----
    $done++
    Write-Output ("`n[{0}/{1}] {2} {3}  ({4})  removing profile..." -f $done, $total, $c.Display, $tag, (Format-Size $c.Size))
    $prof = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { $_.SID -eq $c.Sid } | Select-Object -First 1
    $removed = $false
    if ($prof) {
        try { $prof | Remove-CimInstance -ErrorAction Stop; $removed = $true }
        catch {
            # CIM/registry removal blocked (often a locked handle); delete the folder directly.
            try { Remove-Item -LiteralPath $c.Path -Recurse -Force -ErrorAction Stop; $removed = $true }
            catch { Log ("[!] FAILED to remove profile {0} ({1}): {2}" -f $c.Path, $c.Display, $_.Exception.Message) }
        }
    } else {
        try { Remove-Item -LiteralPath $c.Path -Recurse -Force -ErrorAction Stop; $removed = $true }
        catch { Log ("[!] FAILED to remove folder {0}: {1}" -f $c.Path, $_.Exception.Message) }
    }

    if ($removed) {
        $totalFreed += $c.Size
        Log ("RECLAIMED profile {0} for {1} {2} (freed {3})" -f $c.Path, $c.Display, $tag, (Format-Size $c.Size))
        if ($Delete) {
            if ($c.IsLocal) {
                try { Remove-LocalUser -SID ([System.Security.Principal.SecurityIdentifier]$c.Sid) -ErrorAction Stop; Log ("DELETED local account {0}" -f $c.Display) }
                catch { Log ("[!] profile removed but FAILED to delete local account {0}: {1}" -f $c.Display, $_.Exception.Message) }
            } elseif (-not $c.Orphaned) {
                Log ("note: {0} is a domain account - profile removed, AD account left intact" -f $c.Display)
            }
        }
    }
    Write-Output ("    {0} of {1} processed, {2} left, {3} reclaimed so far." -f $done, $total, ($total - $done), (Format-Size $totalFreed))
}

if ($Force) {
    Write-Output ("`nTOTAL DISK RECLAIMED: {0}" -f (Format-Size $totalFreed))
    Write-Output "Action log: $logFile"
} else {
    Write-Output ("`nTOTAL RECLAIMABLE: {0} (re-run with -Force to apply)" -f (Format-Size $totalPotential))
    Write-Output "Dry run complete. Re-run with -Force to remove the profiles above."
}
Write-Output "Note: removing a profile deletes that user's C:\Users folder. Domain/AD accounts are left intact (only the local profile is cleared); add -Delete to also remove LOCAL accounts."
Write-Output "Note: if Windows still shows the space as used afterward, System Protection / shadow copies (VSS) may be holding the freed data - Windows purges that only when space is needed. Check with: vssadmin list shadowstorage"
