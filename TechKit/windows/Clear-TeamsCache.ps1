<#
.SYNOPSIS
    Clear the Microsoft Teams cache to fix freezes, blank screens, stale presence, and login loops.
    Handles both classic Teams and new Teams (MSIX). DRY-RUN BY DEFAULT. Does not sign you out of files.
.DESCRIPTION
    Closes Teams, then clears its cache folders. Teams rebuilds them on next launch. Chats/teams
    live in the cloud and re-download — nothing of yours is lost. No admin needed (per-user).
.PARAMETER Force
    Actually clear the cache. Without it, preview only.
#>
[CmdletBinding()]
param([switch]$Force)

$mode = if ($Force) { "EXECUTE" } else { "DRY RUN (add -Force to apply)" }
Write-Output "=== Clear Microsoft Teams Cache ==="
Write-Output "Mode: $mode`n"

# Close both Teams variants
$procs = @("Teams","ms-teams")
if ($Force) { foreach ($p in $procs) { Stop-Process -Name $p -Force -ErrorAction SilentlyContinue }; Start-Sleep -Seconds 2 }
else { Write-Output "  WOULD close Teams (Teams.exe / ms-teams.exe)" }

$freed = 0
function ClearDir($path, $label) {
    if (-not (Test-Path $path)) { return }
    $sizeMB = [math]::Round(((Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)/1MB,1)
    if ($Force) {
        Get-ChildItem $path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output "  CLEARED $label ($sizeMB MB)"
        $script:freed += $sizeMB
    } else { Write-Output "  WOULD clear $label ($sizeMB MB)" }
}

Write-Output "=== Classic Teams ==="
$classic = "$env:APPDATA\Microsoft\Teams"
if (Test-Path $classic) {
    foreach ($sub in "Cache","blob_storage","databases","GPUCache","IndexedDB","Local Storage","tmp","Service Worker","Code Cache","Application Cache") {
        ClearDir (Join-Path $classic $sub) "Teams\$sub"
    }
} else { Write-Output "  (classic Teams not present)" }

Write-Output "`n=== New Teams (MSIX) ==="
$newTeams = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory -Filter "MSTeams_*" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($newTeams) {
    $lc = Join-Path $newTeams.FullName "LocalCache"
    ClearDir $lc "MSTeams LocalCache"
} else { Write-Output "  (new Teams not present)" }

Write-Output ""
if ($Force) {
    Write-Output ("Done. ~{0} MB cleared. Relaunch Teams; first start will be slower while it rebuilds the cache." -f $freed)
} else {
    Write-Output "Dry run complete. Re-run with -Force to apply."
}
