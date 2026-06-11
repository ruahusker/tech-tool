<#
.SYNOPSIS
    Repair a broken Windows Update by resetting its components. DRY-RUN BY DEFAULT; requires admin.
.DESCRIPTION
    Automates the standard (and extended) Windows Update reset:
      1. Stops the update-related services (wuauserv, BITS, cryptsvc, msiserver).
      2. Renames SoftwareDistribution and catroot2 to timestamped .old folders (reversible —
         Windows rebuilds them). Falls back to clearing contents if a rename is blocked.
      3. Clears the BITS transfer queue (qmgr*.dat).
      4. Restarts the services and restores their correct startup types.
      5. Triggers a fresh update scan so you can confirm it works before leaving.
    Without -Force this only PREVIEWS the steps. Every action is logged to ..\collections.
    Optional deeper repairs:
      -RepairImage : also run DISM /RestoreHealth + SFC /scannow (fixes component-store
                     corruption — a common hidden cause; adds 15-45 min).
      -DeepReset   : also re-register Windows Update / BITS DLLs and reset Winsock
                     (for stubborn cases; a reboot is required afterward).
.PARAMETER Force
    Actually perform the repair. Without it, dry-run preview only.
.PARAMETER RepairImage
    Additionally run DISM RestoreHealth and SFC /scannow.
.PARAMETER DeepReset
    Additionally re-register WU/BITS components and reset Winsock (aggressive; reboot after).
.PARAMETER SkipCatroot2
    Leave catroot2 untouched (rename SoftwareDistribution only).
.EXAMPLE
    .\Repair-WindowsUpdate.ps1                 # preview the steps
    .\Repair-WindowsUpdate.ps1 -Force          # standard reset
    .\Repair-WindowsUpdate.ps1 -Force -RepairImage   # reset + component-store repair
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$RepairImage,
    [switch]$DeepReset,
    [switch]$SkipCatroot2
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Output "[!] This repair requires an elevated (Run as administrator) PowerShell. Aborting."; exit 1 }

$mode = if ($Force) { "EXECUTE" } else { "DRY RUN (preview only; add -Force to apply)" }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $PSScriptRoot ("..\collections\{0}-winupdate-repair-{1}.log" -f $env:COMPUTERNAME, $stamp)
function Log($msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Write-Output "  $msg"
    if ($Force) { try { New-Item -ItemType Directory -Force -Path (Split-Path $logFile) | Out-Null; Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue } catch {} }
}

# Services involved in Windows Update, with the startup type they should end up at.
$svcPlan = @(
    @{ Name = "wuauserv";  Start = "Manual" }   # Windows Update
    @{ Name = "bits";      Start = "Manual" }   # Background Intelligent Transfer
    @{ Name = "cryptsvc";  Start = "Automatic" } # Cryptographic Services
    @{ Name = "msiserver"; Start = "Manual" }   # Windows Installer
    @{ Name = "usosvc";    Start = "Manual" }   # Update Orchestrator (Win10/11)
)

Write-Output "=== Windows Update Repair ==="
Write-Output "Mode: $mode  |  Host: $env:COMPUTERNAME"
Write-Output ""

# Pre-flight: free space on system drive (WU needs room to stage).
$sys = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
$freeGB = [math]::Round($sys.FreeSpace/1GB,1)
Write-Output "Free space on $($env:SystemDrive): $freeGB GB"
if ($freeGB -lt 10) { Write-Output "  [!] Low disk space can itself cause update failures. Consider Clear-TempFiles.ps1 / Find-LargeFiles.ps1." }
Write-Output ""

Write-Output "=== STEP 1: stop services ==="
foreach ($s in $svcPlan) {
    $svc = Get-Service $s.Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Output "  (skip $($s.Name) - not present)"; continue }
    if ($Force) {
        Stop-Service $s.Name -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 400
        $state = (Get-Service $s.Name -ErrorAction SilentlyContinue).Status
        Log ("Stopped {0} (now {1})" -f $s.Name, $state)
    } else {
        Write-Output ("  WOULD stop {0} (currently {1})" -f $s.Name, $svc.Status)
    }
}

# Helper: rename a folder to <name>.old-<stamp>; if blocked, clear its contents.
function Reset-Folder($path, $label) {
    if (-not (Test-Path $path)) { Write-Output "  ($label not found: $path)"; return }
    if (-not $Force) { Write-Output "  WOULD rename $label -> $(Split-Path $path -Leaf).old-$stamp (Windows rebuilds it)"; return }
    $target = "$path.old-$stamp"
    try {
        Rename-Item -Path $path -NewName (Split-Path $target -Leaf) -ErrorAction Stop
        Log ("Renamed $label to $target")
    } catch {
        Log ("Rename of $label blocked (in use); clearing its contents instead")
        Get-ChildItem $path -Force -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Output "`n=== STEP 2: reset update caches ==="
Reset-Folder "$env:windir\SoftwareDistribution" "SoftwareDistribution"
if (-not $SkipCatroot2) { Reset-Folder "$env:windir\System32\catroot2" "catroot2" }
else { Write-Output "  (skipping catroot2 per -SkipCatroot2)" }

Write-Output "`n=== STEP 3: clear BITS transfer queue ==="
$bitsQueue = "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader"
if (Test-Path $bitsQueue) {
    if ($Force) {
        Get-ChildItem $bitsQueue -Filter "qmgr*.dat" -Force -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
        Log "Cleared BITS queue (qmgr*.dat) in $bitsQueue"
    } else { Write-Output "  WOULD delete qmgr*.dat in $bitsQueue" }
} else { Write-Output "  (BITS queue folder not found)" }

if ($DeepReset) {
    Write-Output "`n=== STEP 3b: deep reset (re-register components + Winsock) ==="
    $dlls = @("atl.dll","urlmon.dll","mshtml.dll","jscript.dll","vbscript.dll","wuapi.dll","wuaueng.dll",
              "wucltux.dll","wups.dll","wups2.dll","wuwebv.dll","qmgr.dll","qmgrprxy.dll","wbem\wmisvc.dll")
    if ($Force) {
        foreach ($d in $dlls) { & regsvr32.exe /s "$env:windir\System32\$d" 2>$null }
        Log "Re-registered Windows Update / BITS DLLs"
        & netsh winsock reset 2>$null | Out-Null
        Log "Reset Winsock catalog (reboot required)"
    } else {
        Write-Output "  WOULD re-register $($dlls.Count) WU/BITS DLLs and run 'netsh winsock reset'"
    }
}

Write-Output "`n=== STEP 4: restart services + restore startup types ==="
foreach ($s in $svcPlan) {
    $svc = Get-Service $s.Name -ErrorAction SilentlyContinue
    if (-not $svc) { continue }
    if ($Force) {
        Set-Service $s.Name -StartupType $s.Start -ErrorAction SilentlyContinue
        if ($s.Name -in @("cryptsvc","bits","wuauserv")) { Start-Service $s.Name -ErrorAction SilentlyContinue }
        Log ("{0}: startup={1}, status={2}" -f $s.Name, $s.Start, (Get-Service $s.Name).Status)
    } else {
        Write-Output ("  WOULD set {0} startup={1} and start it" -f $s.Name, $s.Start)
    }
}

if ($RepairImage) {
    Write-Output "`n=== STEP 5: component-store repair (DISM + SFC) — this can take 15-45 minutes ==="
    if ($Force) {
        Write-Output "  Running DISM /Online /Cleanup-Image /RestoreHealth ..."
        & DISM /Online /Cleanup-Image /RestoreHealth
        Write-Output "  Running sfc /scannow ..."
        & sfc /scannow
        Log "Ran DISM RestoreHealth + SFC scannow"
    } else {
        Write-Output "  WOULD run DISM /Online /Cleanup-Image /RestoreHealth then sfc /scannow"
    }
}

Write-Output "`n=== STEP 6: trigger a fresh update scan ==="
if ($Force) {
    if (Get-Command UsoClient -ErrorAction SilentlyContinue) { & UsoClient StartScan 2>$null; Log "Triggered update scan via UsoClient" }
    else { & wuauclt /resetauthorization /detectnow 2>$null; Log "Triggered update scan via wuauclt" }
} else { Write-Output "  WOULD trigger an update detection scan" }

Write-Output ""
if ($Force) {
    Write-Output "Repair complete. Action log: $logFile"
    if ($DeepReset) { Write-Output "[!] -DeepReset reset Winsock — REBOOT before testing updates." }
    Write-Output "Next: reboot, then Settings > Windows Update > Check for updates. Renamed .old folders can be deleted once updates succeed."
} else {
    Write-Output "Dry run complete. Re-run with -Force to apply. Add -RepairImage for component-store repair, -DeepReset for stubborn cases."
}
