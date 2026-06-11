<#
.SYNOPSIS
    Clean temp files, Windows Update download cache, and optionally the Recycle Bin. DRY-RUN BY DEFAULT.
.DESCRIPTION
    DESTRUCTIVE (mildly) - without -Force it only reports sizes. Targets only well-known
    safe-to-delete locations. Files in use are skipped automatically.
.PARAMETER IncludeWindowsUpdate
    Also purge C:\Windows\SoftwareDistribution\Download (stops/starts wuauserv; needs admin).
.PARAMETER IncludeRecycleBin
    Also empty the Recycle Bin for all drives.
.PARAMETER Force
    Actually delete. Without this, dry-run report only.
.EXAMPLE
    .\Clear-TempFiles.ps1                          # see what would be freed
    .\Clear-TempFiles.ps1 -Force -IncludeRecycleBin
#>
[CmdletBinding()]
param(
    [switch]$IncludeWindowsUpdate,
    [switch]$IncludeRecycleBin,
    [switch]$Force
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$mode = if ($Force) { "EXECUTE" } else { "DRY RUN (add -Force to delete)" }
Write-Output "Mode: $mode`n"

function Measure-Folder($p) {
    if (-not (Test-Path $p)) { return 0 }
    (Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
}
function Clear-Folder($p) {
    # Delete contents, not the folder itself; in-use files fail silently and are kept.
    Get-ChildItem $p -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$targets = @(
    @{ Name = "User temp ($env:TEMP)"; Path = $env:TEMP; NeedsAdmin = $false }
    @{ Name = "Windows temp"; Path = "$env:windir\Temp"; NeedsAdmin = $true }
    @{ Name = "Windows error reports"; Path = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"; NeedsAdmin = $true }
    @{ Name = "Thumbnail/icon cache"; Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; NeedsAdmin = $false }
)

$totalFreed = 0
foreach ($t in $targets) {
    $size = Measure-Folder $t.Path
    $sizeMB = [math]::Round($size/1MB)
    if ($t.NeedsAdmin -and -not $isAdmin) { Write-Output ("  SKIP (needs admin)  {0,8} MB  {1}" -f $sizeMB, $t.Name); continue }
    if ($Force -and $size -gt 0) {
        Clear-Folder $t.Path
        $after = Measure-Folder $t.Path
        $freed = $size - $after
        $totalFreed += $freed
        Write-Output ("  CLEANED  {0,8} MB freed  {1}  ({2} MB in-use kept)" -f [math]::Round($freed/1MB), $t.Name, [math]::Round($after/1MB))
    } else {
        Write-Output ("  WOULD CLEAN  {0,8} MB  {1}" -f $sizeMB, $t.Name)
        $totalFreed += $size
    }
}

if ($IncludeWindowsUpdate) {
    $wuPath = "$env:windir\SoftwareDistribution\Download"
    $size = Measure-Folder $wuPath
    if (-not $isAdmin) { Write-Output ("  SKIP (needs admin)  {0,8} MB  Windows Update download cache" -f [math]::Round($size/1MB)) }
    elseif ($Force) {
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        Clear-Folder $wuPath
        Start-Service wuauserv -ErrorAction SilentlyContinue
        $totalFreed += $size
        Write-Output ("  CLEANED  {0,8} MB  Windows Update download cache" -f [math]::Round($size/1MB))
    } else { Write-Output ("  WOULD CLEAN  {0,8} MB  Windows Update download cache" -f [math]::Round($size/1MB)); $totalFreed += $size }
}

if ($IncludeRecycleBin) {
    $rb = (Get-ChildItem "$env:SystemDrive\`$Recycle.Bin" -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($Force) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        $totalFreed += $rb
        Write-Output ("  EMPTIED  {0,8} MB  Recycle Bin" -f [math]::Round($rb/1MB))
    } else { Write-Output ("  WOULD EMPTY  {0,8} MB  Recycle Bin" -f [math]::Round($rb/1MB)); $totalFreed += $rb }
}

Write-Output ("`nTotal {0}: {1:N1} GB" -f $(if($Force){"freed"}else{"reclaimable"}), ($totalFreed/1GB))
Write-Output "Not touched on purpose: browser profiles/caches, Downloads, app data. For bigger wins see Find-LargeFiles.ps1."
