<#
.SYNOPSIS
    Deep uninstall of Adobe Creative Cloud and its apps, including the services, tasks, and
    leftovers a normal uninstall misses. Clears licensing + sign-in so it re-authenticates.
    DRY-RUN BY DEFAULT; requires admin.
.DESCRIPTION
    Order of operations:
      1. Inventory installed Adobe products.
      2. Stop Adobe background processes (Creative Cloud, Core Sync, Adobe Genuine, IPC broker...).
      3. Stop + delete Adobe services (AGSService, AGMService, AdobeUpdateService, AdobeARMservice...).
      4. Run the supported uninstallers (Creative Cloud Uninstaller + each app's uninstall string).
      5. Remove leftover folders, registry keys, and scheduled tasks.
      6. Clear licensing (SLStore/SLCache) and sign-in (OOBE) so a reinstall requires fresh login.
    SAFETY: Never touches your creative files (Documents/Pictures/Desktop). Keeps the free Adobe
    Acrobat Reader by default (-RemoveAll includes it). Optionally cleans Adobe activation-blocking
    lines from the hosts file (-CleanHosts, backed up first). Dry-run unless -Force; logs to ..\collections.
.PARAMETER Force
    Actually perform the removal. Without it, preview only.
.PARAMETER RemoveAll
    Also remove the free Adobe Acrobat Reader (kept by default).
.PARAMETER CleanHosts
    Remove Adobe license-server entries from the hosts file (common with cracked installs). Backs up hosts first.
.EXAMPLE
    .\Remove-AdobeCreativeCloud.ps1          # preview
    .\Remove-AdobeCreativeCloud.ps1 -Force   # deep uninstall
#>
[CmdletBinding()]
param([switch]$Force, [switch]$RemoveAll, [switch]$CleanHosts)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Output "[!] This requires an elevated PowerShell. Aborting."; exit 1 }

$mode = if ($Force) { "EXECUTE" } else { "DRY RUN (preview only; add -Force to apply)" }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $PSScriptRoot ("..\collections\{0}-adobe-removal-{1}.log" -f $env:COMPUTERNAME, $stamp)
function Log($m) { Write-Output "  $m"; if ($Force) { try { New-Item -ItemType Directory -Force -Path (Split-Path $logFile) | Out-Null; Add-Content -Path $logFile -Value ("{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m) -ErrorAction SilentlyContinue } catch {} } }
function Do-Or-Preview($desc, [scriptblock]$act) { if ($Force) { try { & $act; Log "DONE: $desc" } catch { Log "FAILED: $desc -> $($_.Exception.Message)" } } else { Write-Output "  WOULD: $desc" } }

Write-Output "=== Adobe Creative Cloud Deep Removal ==="
Write-Output "Mode: $mode  |  Host: $env:COMPUTERNAME"
Write-Output ""

# ---------- inventory ----------
Write-Output "=== Installed Adobe products ==="
$arp = @()
foreach ($root in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")) {
    $arp += Get-ItemProperty $root -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and ($_.Publisher -match "Adobe" -or $_.DisplayName -match "Adobe") }
}
$keepReader = -not $RemoveAll
if ($keepReader) { $arp = $arp | Where-Object { $_.DisplayName -notmatch "Acrobat Reader" } }
if ($arp) { $arp | ForEach-Object { Write-Output ("  {0}  {1}" -f $_.DisplayName, $_.DisplayVersion) } }
else { Write-Output "  No Adobe products found in the uninstall registry." }
if ($keepReader) { Write-Output "  (keeping free Adobe Acrobat Reader — use -RemoveAll to remove it too)" }
Write-Output ""

# ---------- stop processes ----------
Write-Output "=== STEP: stop Adobe processes ==="
$procs = @("Creative Cloud","Creative Cloud Helper","CCXProcess","CCLibrary","CoreSync","Core Sync",
           "Adobe Desktop Service","AdobeIPCBroker","AdobeNotificationClient","AdobeUpdateService",
           "AdobeGCClient","AGSService","AGMService","AdobeCollabSync","Adobe CEF Helper","AdobeARM",
           "Photoshop","Illustrator","AfterFX","Adobe Premiere Pro","Acrobat","AcroCEF","Lightroom","Bridge","InDesign")
foreach ($p in $procs) {
    $clean = $p -replace ' ',''
    if (Get-Process -Name $clean -ErrorAction SilentlyContinue) {
        Do-Or-Preview "stop process $p" { Stop-Process -Name ($p -replace ' ','') -Force -ErrorAction SilentlyContinue }
    }
}
Write-Output ""

# ---------- services ----------
Write-Output "=== STEP: stop + remove Adobe services ==="
Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { ($_.Name -match "Adobe|AGSService|AGMService|AdobeARM") -or ($_.DisplayName -match "Adobe") } | ForEach-Object {
    $svc = $_
    Do-Or-Preview "stop+delete service $($svc.Name) ($($svc.DisplayName))" { Stop-Service $svc.Name -Force -ErrorAction SilentlyContinue; & sc.exe delete $svc.Name | Out-Null }
}
Write-Output ""

# ---------- supported uninstallers ----------
Write-Output "=== STEP: run supported uninstallers ==="
$ccUninstaller = "$env:ProgramFiles\Adobe\Adobe Creative Cloud\Utils\Creative Cloud Uninstaller.exe"
foreach ($a in $arp) {
    $cmd = $a.QuietUninstallString; if (-not $cmd) { $cmd = $a.UninstallString }
    if (-not $cmd) { continue }
    Do-Or-Preview "uninstall $($a.DisplayName)" { Start-Process "cmd.exe" -ArgumentList "/c", $cmd -Wait -WindowStyle Hidden }
}
if (Test-Path $ccUninstaller) {
    Do-Or-Preview "run Creative Cloud Uninstaller" { Start-Process $ccUninstaller -ArgumentList "-uninstall=1" -Wait }
}
Write-Output ""

# ---------- leftover folders ----------
Write-Output "=== STEP: remove leftover folders ==="
$folders = @(
    "$env:ProgramFiles\Adobe", "${env:ProgramFiles(x86)}\Adobe",
    "$env:ProgramFiles\Common Files\Adobe", "${env:ProgramFiles(x86)}\Common Files\Adobe",
    "$env:ProgramData\Adobe", "$env:LOCALAPPDATA\Adobe", "$env:APPDATA\Adobe",
    "$env:ProgramData\Package Cache\Adobe"
)
foreach ($f in $folders) {
    if (Test-Path $f) {
        if ($keepReader -and (Test-Path "$f\Acrobat")) { Write-Output "  [!] SKIP $f (contains Acrobat Reader; -RemoveAll to include)"; continue }
        $sizeMB = [math]::Round(((Get-ChildItem $f -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)/1MB,1)
        Do-Or-Preview "remove $f ($sizeMB MB)" { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
Write-Output ""

# ---------- registry ----------
Write-Output "=== STEP: remove Adobe registry keys ==="
foreach ($k in @("HKLM:\SOFTWARE\Adobe","HKLM:\SOFTWARE\WOW6432Node\Adobe","HKCU:\Software\Adobe")) {
    if (Test-Path $k) { Do-Or-Preview "delete registry key $k" { Remove-Item $k -Recurse -Force -ErrorAction SilentlyContinue } }
}
Write-Output ""

# ---------- scheduled tasks ----------
Write-Output "=== STEP: remove Adobe scheduled tasks ==="
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match "Adobe|CCXProcess|CreativeCloud|AdobeGCInvoker" } | ForEach-Object {
    Do-Or-Preview "unregister task $($_.TaskName)" { Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue }
}
Write-Output ""

# ---------- hosts (optional) ----------
if ($CleanHosts) {
    Write-Output "=== STEP: clean Adobe license-blocking entries from hosts ==="
    $hosts = "$env:windir\System32\drivers\etc\hosts"
    $adobeLines = Select-String -Path $hosts -Pattern "adobe" -ErrorAction SilentlyContinue
    if ($adobeLines) {
        $adobeLines | ForEach-Object { Write-Output "    found: $($_.Line)" }
        Do-Or-Preview "back up hosts and remove $($adobeLines.Count) Adobe line(s)" {
            Copy-Item $hosts "$hosts.bak-$stamp" -Force
            (Get-Content $hosts) | Where-Object { $_ -notmatch "adobe" } | Set-Content $hosts -Force
        }
    } else { Write-Output "  No Adobe entries in hosts." }
    Write-Output ""
}

# ---------- licensing + sign-in (forces re-auth) ----------
Write-Output "=== STEP: clear licensing + sign-in (forces re-authentication) ==="
foreach ($f in @("$env:ProgramData\Adobe\SLStore","$env:ProgramData\Adobe\SLCache",
                 "$env:LOCALAPPDATA\Adobe\OOBE","$env:APPDATA\Adobe\OOBE")) {
    if (Test-Path $f) { Do-Or-Preview "clear $f" { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue } }
}

Write-Output ""
if ($Force) {
    Write-Output "Complete. Action log: $logFile"
    Write-Output "[!] REBOOT now. After reboot, reinstall Creative Cloud; first launch requires a fresh sign-in."
    Write-Output "Official deep-clean fallback for stubborn cases: Adobe Creative Cloud Cleaner Tool."
} else {
    Write-Output "Dry run complete. Re-run with -Force to apply. Add -CleanHosts to fix activation-blocking hosts entries, -RemoveAll to also remove Acrobat Reader."
}
