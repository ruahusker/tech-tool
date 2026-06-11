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
    Delete accounts instead of disabling them.
.PARAMETER RemoveProfile
    With -Delete: also remove the user's C:\Users profile folder and registry hive.
.PARAMETER IncludeNeverLoggedOn
    Also act on accounts with no recorded logon (off by default - these are often service accounts).
.PARAMETER Exclude
    Additional account names to protect, e.g. -Exclude svc_backup,kiosk
.PARAMETER Force
    Actually perform the actions. Without this, dry-run only.
.EXAMPLE
    .\Remove-InactiveUsers.ps1 -DaysInactive 90                  # dry run: show candidates
    .\Remove-InactiveUsers.ps1 -DaysInactive 90 -Force           # disable them
    .\Remove-InactiveUsers.ps1 -DaysInactive 180 -Delete -RemoveProfile -Force
#>
[CmdletBinding()]
param(
    [int]$DaysInactive = 90,
    [switch]$Delete,
    [switch]$RemoveProfile,
    [switch]$IncludeNeverLoggedOn,
    [string[]]$Exclude = @(),
    [switch]$Force
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Force -and -not $isAdmin) { Write-Output "[!] -Force requires an elevated PowerShell. Aborting."; exit 1 }

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

foreach ($u in $candidates) {
    $last = if ($u.LastLogon) { $u.LastLogon.ToString('yyyy-MM-dd') } else { "never" }
    if (-not $Force) {
        Write-Output ("  WOULD {0}  {1,-22} (last logon {2})" -f $action, $u.Name, $last)
        continue
    }
    try {
        if ($Delete) {
            Remove-LocalUser -Name $u.Name -ErrorAction Stop
            Log ("DELETED user {0} (last logon {1})" -f $u.Name, $last)
            if ($RemoveProfile) {
                $prof = Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -like "*\$($u.Name)" -and -not $_.Special -and -not $_.Loaded }
                if ($prof) { $prof | Remove-CimInstance; Log ("REMOVED profile {0}" -f $prof.LocalPath) }
                elseif (Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -like "*\$($u.Name)" -and $_.Loaded }) {
                    Log ("PROFILE for {0} is loaded (in use) - not removed" -f $u.Name)
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

if ($Force) { Write-Output "`nAction log: $logFile" }
else { Write-Output "`nDry run complete. Re-run with -Force to apply the $action actions above." }
Write-Output "Tip: disabling is reversible (Enable-LocalUser); prefer it over -Delete unless storage must be reclaimed."
