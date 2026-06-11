<#
.SYNOPSIS
    Reset OneDrive to fix stuck/failed sync. Re-syncs from the cloud; does NOT delete your files.
.DESCRIPTION
    Runs 'onedrive.exe /reset' (clears the sync state and reconnects), then relaunches OneDrive.
    Your synced files stay on disk and re-sync. DRY-RUN BY DEFAULT (no admin needed — per-user).
.PARAMETER Force
    Actually perform the reset. Without it, preview only.
.EXAMPLE
    .\Reset-OneDrive.ps1 -Force
#>
[CmdletBinding()]
param([switch]$Force)

$paths = @(
    "$env:LOCALAPPDATA\Microsoft\OneDrive\onedrive.exe",
    "$env:ProgramFiles\Microsoft OneDrive\onedrive.exe",
    "${env:ProgramFiles(x86)}\Microsoft OneDrive\onedrive.exe",
    "$env:SystemRoot\System32\OneDriveSetup.exe"
)
$exe = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { Write-Output "[!] OneDrive executable not found. Is OneDrive installed?"; exit 1 }

$mode = if ($Force) { "EXECUTE" } else { "DRY RUN (add -Force to apply)" }
Write-Output "=== Reset OneDrive ==="
Write-Output "Mode: $mode"
Write-Output "OneDrive: $exe"
Write-Output "Your files are NOT deleted — OneDrive re-syncs them after the reset.`n"

if ($Force) {
    Write-Output "  Stopping OneDrive..."
    Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Output "  Running OneDrive /reset..."
    Start-Process $exe -ArgumentList "/reset"
    Write-Output "  Waiting for reset to complete (up to 90s)..."
    for ($i=0; $i -lt 18; $i++) { Start-Sleep -Seconds 5; if (-not (Get-Process OneDrive -ErrorAction SilentlyContinue)) { break } }
    Write-Output "  Relaunching OneDrive..."
    Start-Process $exe
    Write-Output "`nDone. OneDrive will reconnect and re-sync (the cloud icon may churn for a few minutes)."
} else {
    Write-Output "  WOULD stop OneDrive, run '$exe /reset', then relaunch it."
    Write-Output "`nDry run complete. Re-run with -Force to apply."
}
