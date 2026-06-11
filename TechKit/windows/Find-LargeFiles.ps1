<#
.SYNOPSIS
    Find what is eating disk space: largest files, largest first-level folders, common space hogs.
.DESCRIPTION
    Read-only. Pair with Clear-TempFiles.ps1. Scanning a whole drive can take minutes.
.PARAMETER Path
    Where to scan (default: the system drive root).
.PARAMETER Top
    Number of files/folders to list (default 25).
.PARAMETER MinSizeMB
    Ignore files smaller than this (default 100).
#>
[CmdletBinding()]
param(
    [string]$Path = "$env:SystemDrive\",
    [int]$Top = 25,
    [int]$MinSizeMB = 100
)

Write-Output "Scanning $Path (this can take a few minutes on a full drive)...`n"

Write-Output "=== TOP $Top FILES >= $MinSizeMB MB ==="
Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -ge $MinSizeMB * 1MB } |
    Sort-Object Length -Descending | Select-Object -First $Top | ForEach-Object {
        Write-Output ("  {0,9:N1} GB  {1}" -f ($_.Length/1GB), $_.FullName)
    }

Write-Output "`n=== FIRST-LEVEL FOLDER SIZES under $Path ==="
Get-ChildItem -Path $Path -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $bytes = (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    [PSCustomObject]@{ GB = [math]::Round(($bytes/1GB),1); Folder = $_.FullName }
} | Sort-Object GB -Descending | Select-Object -First 15 | ForEach-Object {
    Write-Output ("  {0,9:N1} GB  {1}" -f $_.GB, $_.Folder)
}

Write-Output "`n=== KNOWN SPACE HOGS ==="
$known = @(
    "$env:windir\SoftwareDistribution\Download",
    "$env:windir\Temp",
    "$env:LOCALAPPDATA\Temp",
    "$env:windir\memory.dmp",
    "$env:SystemDrive\hiberfil.sys",
    "$env:SystemDrive\pagefile.sys",
    "$env:SystemDrive\Windows.old"
)
foreach ($k in $known) {
    if (Test-Path $k) {
        $item = Get-Item $k -Force -ErrorAction SilentlyContinue
        $bytes = if ($item.PSIsContainer) { (Get-ChildItem $k -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } else { $item.Length }
        if ($bytes -gt 100MB) { Write-Output ("  {0,9:N1} GB  {1}" -f ($bytes/1GB), $k) }
    }
}
$rb = (Get-ChildItem "$env:SystemDrive\`$Recycle.Bin" -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
if ($rb -gt 100MB) { Write-Output ("  {0,9:N1} GB  Recycle Bin" -f ($rb/1GB)) }

Write-Output "`nHints: Windows.old auto-deletes after 10 days, or remove via Disk Cleanup (admin)."
Write-Output "hiberfil.sys: 'powercfg /h off' reclaims it if hibernation is not needed. Use Clear-TempFiles.ps1 for temp/WU caches."
