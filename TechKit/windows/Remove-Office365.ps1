<#
.SYNOPSIS
    Deep uninstall of Microsoft 365 / Office 365, including leftovers a normal uninstall misses,
    and clears cached sign-in/licensing so products re-authenticate. DRY-RUN BY DEFAULT; admin required.
.DESCRIPTION
    Order of operations (full uninstall):
      1. Inventory installed Office products (Click-to-Run and MSI).
      2. Close all Office apps.
      3. Run the SUPPORTED uninstall (the product's own QuietUninstallString / msiexec).
      4. Remove leftover folders, registry keys, scheduled tasks, and the ClickToRun service
         that a normal uninstall leaves behind.
      5. Clear cached identity, credentials, and licensing tokens so a reinstall forces a
         fresh sign-in / re-activation.

    SAFETY: This NEVER deletes Outlook .pst files or anything under the user's Documents.
    Outlook profile data is left alone unless you pass -RemoveOutlookData (which removes only
    .ost cache files, never .pst). Dry-run by default; -Force is required to make changes, and
    every action is logged to ..\collections.

.PARAMETER Force
    Actually perform the actions. Without it, preview only.
.PARAMETER ResetActivationOnly
    Do NOT uninstall. Only clear cached Office identity/credentials/licensing so the installed
    products re-prompt for sign-in. Fixes "Office is signed into the wrong account / won't
    activate" without reinstalling.
.PARAMETER RemoveOutlookData
    Also remove the Outlook OST cache (rebuilds on next sync). Never removes .pst files.
.EXAMPLE
    .\Remove-Office365.ps1                       # preview a full deep uninstall
    .\Remove-Office365.ps1 -Force                # full deep uninstall + clear sign-in
    .\Remove-Office365.ps1 -ResetActivationOnly -Force   # just force re-sign-in, keep Office
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$ResetActivationOnly,
    [switch]$RemoveOutlookData
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Force -and -not $isAdmin) { Write-Output "[!] -Force requires an elevated PowerShell. Aborting."; exit 1 }

$mode = if ($Force) { "EXECUTE" } else { "DRY RUN (preview only; add -Force to apply)" }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $PSScriptRoot ("..\collections\{0}-office-removal-{1}.log" -f $env:COMPUTERNAME, $stamp)
function Log($msg) {
    Write-Output "  $msg"
    if ($Force) { try { New-Item -ItemType Directory -Force -Path (Split-Path $logFile) | Out-Null; Add-Content -Path $logFile -Value ("{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg) -ErrorAction SilentlyContinue } catch {} }
}
function Do-Or-Preview($desc, [scriptblock]$action) {
    if ($Force) { try { & $action; Log "DONE: $desc" } catch { Log "FAILED: $desc -> $($_.Exception.Message)" } }
    else { Write-Output "  WOULD: $desc" }
}

Write-Output "=== Microsoft 365 / Office Deep Removal ==="
Write-Output "Mode: $mode  |  Host: $env:COMPUTERNAME  |  $(if($ResetActivationOnly){'RESET ACTIVATION ONLY'}else{'FULL UNINSTALL'})"
Write-Output ""

# ---------- inventory ----------
Write-Output "=== Installed Office products ==="
$c2rConfig = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
if (Test-Path $c2rConfig) {
    $cfg = Get-ItemProperty $c2rConfig -ErrorAction SilentlyContinue
    Write-Output ("  Click-to-Run: {0}" -f $cfg.ProductReleaseIds)
    Write-Output ("  Version: {0}  Platform: {1}" -f $cfg.VersionToReport, $cfg.Platform)
}
$arp = @()
foreach ($root in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*")) {
    $arp += Get-ItemProperty $root -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -and ($_.DisplayName -match "Microsoft (365|Office)" -or $_.DisplayName -match "Office 16")
    }
}
$arp | ForEach-Object { Write-Output ("  ARP: {0}" -f $_.DisplayName) }
if (-not (Test-Path $c2rConfig) -and -not $arp) { Write-Output "  No Microsoft 365 / Office installation detected." }

# ---------- close apps ----------
if (-not $ResetActivationOnly) {
    Write-Output "`n=== STEP: close Office apps ==="
    $apps = @("winword","excel","powerpnt","outlook","onenote","onenotem","msaccess","mspub","lync","officeclicktorun","OfficeC2RClient","AppVShNotify")
    foreach ($p in $apps) {
        if (Get-Process $p -ErrorAction SilentlyContinue) {
            Do-Or-Preview "stop process $p" { Stop-Process -Name $p -Force -ErrorAction SilentlyContinue }
        }
    }
}

# ---------- supported uninstall ----------
if (-not $ResetActivationOnly) {
    Write-Output "`n=== STEP: run supported uninstall ==="
    $ran = $false
    foreach ($a in $arp) {
        $cmd = $a.QuietUninstallString; if (-not $cmd) { $cmd = $a.UninstallString }
        if (-not $cmd) { continue }
        $ran = $true
        # C2R uninstalls run via OfficeClickToRun.exe; MSI via msiexec /x {code}
        if ($cmd -match "msiexec") {
            $code = ($cmd -replace '.*?(\{[0-9A-Fa-f\-]+\}).*', '$1')
            Do-Or-Preview "msiexec uninstall $($a.DisplayName) ($code)" { Start-Process msiexec.exe -ArgumentList "/x $code /qn /norestart" -Wait }
        } else {
            $exe = ($cmd -split '"')[1]; if (-not $exe) { $exe = ($cmd -split ' ')[0] }
            $args = $cmd.Substring($cmd.IndexOf($exe) + $exe.Length).Trim('"',' ')
            if ($args -notmatch "DisplayLevel") { $args += " DisplayLevel=False" }
            Do-Or-Preview "Click-to-Run uninstall $($a.DisplayName)" { Start-Process $exe -ArgumentList $args -Wait }
        }
    }
    if (-not $ran) { Write-Output "  (no ARP uninstall entry found; proceeding to manual leftover cleanup)" }
}

# ---------- leftover folders ----------
if (-not $ResetActivationOnly) {
    Write-Output "`n=== STEP: remove leftover folders ==="
    $folders = @(
        "$env:ProgramFiles\Microsoft Office",
        "${env:ProgramFiles(x86)}\Microsoft Office",
        "$env:ProgramFiles\Microsoft Office 15",
        "$env:ProgramFiles\Microsoft Office 16",
        "$env:CommonProgramFiles\microsoft shared\ClickToRun",
        "$env:ProgramData\Microsoft\ClickToRun",
        "$env:ProgramData\Microsoft\office",
        "$env:LOCALAPPDATA\Microsoft\Office",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Office Tools"
    )
    foreach ($f in $folders) {
        if (Test-Path $f) {
            # Guard: never remove anything under the user's Documents, and skip if it holds a .pst
            if ((Get-ChildItem $f -Recurse -Filter *.pst -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                Write-Output "  [!] SKIP $f — contains .pst files (user data); not removing"
                continue
            }
            $sizeMB = [math]::Round(((Get-ChildItem $f -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)/1MB,1)
            Do-Or-Preview "remove $f ($sizeMB MB)" { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    if ($RemoveOutlookData) {
        Write-Output "  Outlook OST cache (.ost only; .pst preserved):"
        Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Outlook" -Filter *.ost -ErrorAction SilentlyContinue | ForEach-Object {
            Do-Or-Preview "remove OST cache $($_.Name)" { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
        }
    } else {
        Write-Output "  (Outlook data left intact — pass -RemoveOutlookData to clear .ost cache; .pst is always preserved)"
    }
}

# ---------- registry leftovers ----------
if (-not $ResetActivationOnly) {
    Write-Output "`n=== STEP: remove leftover registry keys ==="
    $keys = @(
        "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun",
        "HKLM:\SOFTWARE\Microsoft\Office\16.0",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\16.0",
        "HKLM:\SOFTWARE\Microsoft\AppVISV",
        "HKCU:\Software\Microsoft\Office\16.0"
    )
    foreach ($k in $keys) {
        if (Test-Path $k) { Do-Or-Preview "delete registry key $k" { Remove-Item $k -Recurse -Force -ErrorAction SilentlyContinue } }
    }
}

# ---------- scheduled tasks + service ----------
if (-not $ResetActivationOnly) {
    Write-Output "`n=== STEP: remove Office scheduled tasks + ClickToRun service ==="
    Get-ScheduledTask -TaskPath "\Microsoft\Office\*" -ErrorAction SilentlyContinue | ForEach-Object {
        Do-Or-Preview "unregister task $($_.TaskName)" { Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue }
    }
    if (Get-Service ClickToRunSvc -ErrorAction SilentlyContinue) {
        Do-Or-Preview "stop + delete ClickToRunSvc service" { Stop-Service ClickToRunSvc -Force -ErrorAction SilentlyContinue; & sc.exe delete ClickToRunSvc | Out-Null }
    }
}

# ---------- clear identity / credentials / licensing (forces re-auth) ----------
Write-Output "`n=== STEP: clear cached sign-in, credentials, and licensing (forces re-authentication) ==="
$identityFolders = @(
    "$env:LOCALAPPDATA\Microsoft\OneAuth",
    "$env:LOCALAPPDATA\Microsoft\IdentityCache",
    "$env:LOCALAPPDATA\Microsoft\Office\Licenses",
    "$env:LOCALAPPDATA\Microsoft\Office\16.0\Licensing"
)
foreach ($f in $identityFolders) {
    if (Test-Path $f) { Do-Or-Preview "clear $f" { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue } }
}
# HKCU Office Identity (removing it forces a fresh sign-in)
foreach ($k in @("HKCU:\Software\Microsoft\Office\16.0\Common\Identity",
                 "HKCU:\Software\Microsoft\Office\16.0\Common\Licensing")) {
    if (Test-Path $k) { Do-Or-Preview "delete $k" { Remove-Item $k -Recurse -Force -ErrorAction SilentlyContinue } }
}
# Credential Manager: remove cached Office/Microsoft identity credentials
Write-Output "  Cached credentials (Credential Manager):"
$creds = (& cmdkey /list) 2>$null | Select-String "Target:" | ForEach-Object { ($_ -split "Target:")[1].Trim() }
$officeCreds = $creds | Where-Object { $_ -match "MicrosoftOffice|MSOpenTech|OneAuthAccount|Microsoft_OC1|ADAL|SSO_POP|MicrosoftAccount|msteams|Office" }
if ($officeCreds) {
    foreach ($t in $officeCreds) { Do-Or-Preview "delete credential '$t'" { & cmdkey /delete:$t | Out-Null } }
} else { Write-Output "  (no Office-related cached credentials found)" }

Write-Output ""
if ($Force) {
    Write-Output "Complete. Action log: $logFile"
    if ($ResetActivationOnly) { Write-Output "Re-open any Office app; it will prompt to sign in / re-activate." }
    else { Write-Output "[!] REBOOT now. After reboot, reinstall Microsoft 365; first launch will require a fresh sign-in." }
    Write-Output "If anything Office-related still lingers, Microsoft's Support and Recovery Assistant (SaRA) is the official deep-clean fallback."
} else {
    Write-Output "Dry run complete. Re-run with -Force to apply."
    Write-Output "Tip: use -ResetActivationOnly to fix wrong-account/activation issues WITHOUT uninstalling."
}
