<#
.SYNOPSIS
    Back up a user's important folders before a reimage/rebuild. PREVIEWS sizes by default;
    add -Force with -Destination to actually copy.
.DESCRIPTION
    Grabs the stuff people cry about losing: Desktop, Documents, Downloads, Pictures, Videos,
    Music, Favorites. By default it just reports how big each folder is so you can size the
    target. With -Force -Destination <path> it copies via robocopy (resumable, preserves
    timestamps) into a host_user-stamped folder and logs the result. Source is never modified.
.PARAMETER User
    Profile to back up (default: current user). Use the folder name under C:\Users.
.PARAMETER Destination
    Target root (e.g. E:\Backups or a share). Required to actually copy.
.PARAMETER Force
    Actually copy. Without it, preview sizes only.
.PARAMETER IncludeProfile
    Copy the entire user profile, not just the common data folders (much larger).
#>
[CmdletBinding()]
param([string]$User = $env:USERNAME,[string]$Destination,[switch]$Force,[switch]$IncludeProfile)

$src = Join-Path "C:\Users" $User
if (-not (Test-Path $src)) { Write-Output ("[!] Profile not found: {0}" -f $src); exit 1 }

$folders = if ($IncludeProfile) { @('') } else { @('Desktop','Documents','Downloads','Pictures','Videos','Music','Favorites') }
$mode = if ($Force) { "EXECUTE" } else { "PREVIEW (add -Force -Destination <path> to copy)" }
Write-Output "=== Backup User Data ==="
Write-Output ("Mode: {0}  |  User: {1}  |  Source: {2}" -f $mode, $User, $src)

function FolderSizeMB($p){
    if (-not (Test-Path $p)) { return $null }
    try { $b = (Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum; return [math]::Round((($b)/1MB),1) } catch { return $null }
}

Write-Output "`n=== Folder Sizes ==="
$total = 0.0
foreach ($f in $folders) {
    $p = if ($f -eq '') { $src } else { Join-Path $src $f }
    $label = if ($f -eq '') { "(entire profile)" } else { $f }
    $mb = FolderSizeMB $p
    if ($null -eq $mb) { Write-Output ("  {0,-16} : (missing/unreadable)" -f $label) }
    else { $total += $mb; Write-Output ("  {0,-16} : {1,10:N1} MB" -f $label, $mb) }
}
Write-Output ("  {0,-16} : {1,10:N1} MB" -f "TOTAL", $total)

if (-not $Force) { Write-Output "`nPreview only. Re-run with -Force -Destination <path> to copy."; return }
if (-not $Destination) { Write-Output "`n[!] -Force requires -Destination <path>. Aborting."; exit 1 }
if (-not (Test-Path $Destination)) { Write-Output ("[!] Destination not found: {0}" -f $Destination); exit 1 }

$stamp = Get-Date -Format yyyyMMdd-HHmmss
$dest = Join-Path $Destination ("{0}_{1}_{2}" -f $env:COMPUTERNAME, $User, $stamp)
$logDir = Join-Path $PSScriptRoot "..\collections"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$log = Join-Path $logDir ("{0}-{1}-backup-{2}.log" -f $env:COMPUTERNAME, $User, $stamp)

Write-Output ("`nCopying to: {0}" -f $dest)
foreach ($f in $folders) {
    $from = if ($f -eq '') { $src } else { Join-Path $src $f }
    if (-not (Test-Path $from)) { continue }
    $to = if ($f -eq '') { $dest } else { Join-Path $dest $f }
    Write-Output ("  robocopy {0} ..." -f (Split-Path $from -Leaf))
    & robocopy $from $to /E /R:1 /W:1 /NFL /NDL /NP /XJ /LOG+:"$log" | Out-Null
}
Write-Output ("Done. Copied to {0}" -f $dest)
Write-Output ("Log: {0}" -f $log)
Write-Output "Open a few files from the backup before wiping the source."
