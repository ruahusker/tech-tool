<#
.SYNOPSIS
    Refresh / repair the SCCM (ConfigMgr) client so stuck deployments and inventory recover.
    DRY-RUN BY DEFAULT; requires admin.
.DESCRIPTION
    Safe tier (default with -Force): triggers the client policy actions (machine + user policy
    retrieval/evaluation, hardware/software inventory, discovery, app & software-update eval),
    clears the ccmcache, and restarts the SMS Agent Host (CcmExec). This fixes the large majority
    of "the deployment never showed up / inventory is stale" tickets.
    Heavier, gated repairs:
      -Repair    : run ccmrepair.exe and reset the client policy (ResetPolicy).
      -RepairWMI : verify the WMI repository and salvage it if inconsistent (WMI corruption is a
                   common hidden cause of a broken SCCM client). Reboot afterward.
.PARAMETER Force
    Actually perform the refresh. Without it, preview only.
.PARAMETER Repair
    Also run ccmrepair and reset client policy.
.PARAMETER RepairWMI
    Also verify/salvage the WMI repository.
.EXAMPLE
    .\Repair-SCCMClient.ps1            # preview
    .\Repair-SCCMClient.ps1 -Force     # refresh policy + inventory + clear cache
    .\Repair-SCCMClient.ps1 -Force -Repair -RepairWMI
#>
[CmdletBinding()]
param([switch]$Force, [switch]$Repair, [switch]$RepairWMI)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Output "[!] Requires an elevated PowerShell. Aborting."; exit 1 }

$ccmExec = "$env:WINDIR\CCM\CcmExec.exe"
if (-not (Test-Path $ccmExec) -and -not (Get-Service CcmExec -ErrorAction SilentlyContinue)) {
    Write-Output "[!] No SCCM/ConfigMgr client detected on this machine. Nothing to do."; exit 0
}

$mode = if ($Force) { "EXECUTE" } else { "DRY RUN (preview only; add -Force to apply)" }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $PSScriptRoot ("..\collections\{0}-sccm-repair-{1}.log" -f $env:COMPUTERNAME, $stamp)
function Log($m){ Write-Output "  $m"; if($Force){try{New-Item -ItemType Directory -Force -Path (Split-Path $logFile)|Out-Null;Add-Content $logFile ("{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$m) -ErrorAction SilentlyContinue}catch{}} }

Write-Output "=== SCCM / ConfigMgr Client Repair ==="
Write-Output "Mode: $mode  |  Host: $env:COMPUTERNAME"
$cli = Get-CimInstance -Namespace root\ccm -ClassName SMS_Client -ErrorAction SilentlyContinue
if ($cli) { Write-Output "Client version: $($cli.ClientVersion)" }
Write-Output ""

$actions = @(
    @{ Id="{00000000-0000-0000-0000-000000000021}"; Name="Machine Policy Retrieval" }
    @{ Id="{00000000-0000-0000-0000-000000000022}"; Name="Machine Policy Evaluation" }
    @{ Id="{00000000-0000-0000-0000-000000000026}"; Name="User Policy Retrieval" }
    @{ Id="{00000000-0000-0000-0000-000000000027}"; Name="User Policy Evaluation" }
    @{ Id="{00000000-0000-0000-0000-000000000001}"; Name="Hardware Inventory" }
    @{ Id="{00000000-0000-0000-0000-000000000002}"; Name="Software Inventory" }
    @{ Id="{00000000-0000-0000-0000-000000000003}"; Name="Discovery Data Collection" }
    @{ Id="{00000000-0000-0000-0000-000000000121}"; Name="Application Deployment Evaluation" }
    @{ Id="{00000000-0000-0000-0000-000000000113}"; Name="Software Updates Scan" }
    @{ Id="{00000000-0000-0000-0000-000000000108}"; Name="Software Updates Deployment Evaluation" }
)

Write-Output "=== STEP: trigger client policy + inventory actions (safe) ==="
foreach ($a in $actions) {
    if ($Force) {
        try { Invoke-CimMethod -Namespace root\ccm -ClassName SMS_Client -MethodName TriggerSchedule -Arguments @{ sScheduleID = $a.Id } -ErrorAction Stop | Out-Null; Log "triggered: $($a.Name)" }
        catch { Log "FAILED to trigger $($a.Name): $($_.Exception.Message)" }
    } else { Write-Output "  WOULD trigger: $($a.Name)" }
}

Write-Output "`n=== STEP: clear ccmcache ==="
$cachePath = "$env:WINDIR\ccmcache"
try {
    $cm = New-Object -ComObject "UIResource.UIResourceMgr" -ErrorAction Stop
    $cache = $cm.GetCacheInfo()
    $elements = $cache.GetCacheElements()
    if ($Force) {
        foreach ($e in $elements) { $cache.DeleteCacheElement($e.CacheElementID) }
        Log "cleared $($elements.Count) ccmcache element(s) via client API"
    } else { Write-Output "  WOULD clear $($elements.Count) ccmcache element(s)" }
} catch {
    # fallback: clear the folder
    if (Test-Path $cachePath) {
        if ($Force) { Get-ChildItem $cachePath -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; Log "cleared $cachePath (folder fallback)" }
        else { Write-Output "  WOULD clear $cachePath" }
    }
}

Write-Output "`n=== STEP: restart SMS Agent Host (CcmExec) ==="
if ($Force) { Restart-Service CcmExec -Force -ErrorAction SilentlyContinue; Log "restarted CcmExec ($((Get-Service CcmExec).Status))" }
else { Write-Output "  WOULD restart CcmExec" }

if ($Repair) {
    Write-Output "`n=== STEP: ccmrepair + reset client policy (gated) ==="
    $repairExe = "$env:WINDIR\CCM\ccmrepair.exe"
    if ($Force) {
        if (Test-Path $repairExe) { Start-Process $repairExe -ErrorAction SilentlyContinue; Log "launched ccmrepair.exe (runs in background)" }
        try { Invoke-CimMethod -Namespace root\ccm -ClassName SMS_Client -MethodName ResetPolicy -Arguments @{ uFlags = [uint32]1 } -ErrorAction Stop | Out-Null; Log "reset client policy (purge)" } catch { Log "ResetPolicy failed: $($_.Exception.Message)" }
    } else { Write-Output "  WOULD run ccmrepair.exe and ResetPolicy(purge)" }
}

if ($RepairWMI) {
    Write-Output "`n=== STEP: verify/salvage WMI repository (gated) ==="
    if ($Force) {
        $v = & winmgmt /verifyrepository 2>&1
        Log "winmgmt /verifyrepository: $v"
        if ($v -match "not consistent|inconsistent") {
            $s = & winmgmt /salvagerepository 2>&1
            Log "winmgmt /salvagerepository: $s  (reboot recommended)"
        } else { Write-Output "  WMI repository reported consistent — no salvage needed." }
    } else { Write-Output "  WOULD verify the WMI repository and salvage it if inconsistent" }
}

Write-Output ""
if ($Force) {
    Write-Output "Done. Action log: $logFile"
    Write-Output "Give the client a few minutes, then check Software Center / Control Panel > Configuration Manager > Actions."
    if ($RepairWMI) { Write-Output "[!] If WMI was salvaged, reboot the machine." }
} else {
    Write-Output "Dry run complete. Re-run with -Force. Add -Repair for ccmrepair, -RepairWMI for WMI corruption."
}
