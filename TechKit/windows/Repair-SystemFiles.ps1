<#
.SYNOPSIS
    System file integrity: diagnose with DISM/SFC, repair with -Repair. Requires admin.
.DESCRIPTION
    Default mode is DIAGNOSE-ONLY (DISM ScanHealth + SFC verifyonly, no changes).
    -Repair runs DISM RestoreHealth then SFC /scannow. Allow 15-60 minutes for repair.
    This is the standard fix chain for: Windows Update failures, missing DLL errors,
    explorer/start-menu corruption, and post-malware cleanup.
.PARAMETER Repair
    Actually repair instead of just diagnosing.
.EXAMPLE
    .\Repair-SystemFiles.ps1            # diagnose only
    .\Repair-SystemFiles.ps1 -Repair    # full repair chain
#>
[CmdletBinding()]
param([switch]$Repair)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Output "[!] This script requires an elevated PowerShell. Aborting."; exit 1 }

if ($Repair) {
    Write-Output "REPAIR MODE - this can take 15-60 minutes. Do not reboot during the run.`n"
    Write-Output "=== 1/2 DISM RestoreHealth (repairs the component store) ==="
    & DISM /Online /Cleanup-Image /RestoreHealth
    Write-Output "`n=== 2/2 SFC /scannow (repairs system files from the store) ==="
    & sfc /scannow
    Write-Output "`nDone. If errors persist: check $env:windir\Logs\CBS\CBS.log and $env:windir\Logs\DISM\dism.log,"
    Write-Output "reboot and re-run once. Two failed cycles usually means an in-place upgrade repair is the next step."
} else {
    Write-Output "DIAGNOSE MODE (no changes). Use -Repair to fix findings.`n"
    Write-Output "=== DISM CheckHealth (fast flag check) ==="
    & DISM /Online /Cleanup-Image /CheckHealth
    Write-Output "`n=== DISM ScanHealth (thorough store scan, a few minutes) ==="
    & DISM /Online /Cleanup-Image /ScanHealth
    Write-Output "`n=== SFC verify-only ==="
    & sfc /verifyonly
    Write-Output "`nIf either reported corruption: re-run this script with -Repair."
}
