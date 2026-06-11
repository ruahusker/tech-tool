<#
.SYNOPSIS
    One-click network repair: flush DNS, reset Winsock/IP stack, renew DHCP, clear ARP, restart adapter.
    DRY-RUN BY DEFAULT; requires admin. Some resets need a reboot to fully take effect.
.DESCRIPTION
    The standard "fix the network" sequence techs run for no-internet / flaky-connection tickets:
    flushes the DNS cache, resets the Winsock catalog and TCP/IP stack, releases+renews DHCP,
    clears the ARP cache, and bounces the active adapter. Pair with Get-NetworkDiagnostics.ps1 to
    confirm the fix.
.PARAMETER Force
    Actually run the repair. Without it, preview only.
.PARAMETER SkipStackReset
    Skip the Winsock/IP reset (those are the parts that need a reboot). Use for a lighter,
    no-reboot refresh (flush DNS + renew DHCP + restart adapter only).
#>
[CmdletBinding()]
param([switch]$Force, [switch]$SkipStackReset)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Output "[!] Requires an elevated PowerShell. Aborting."; exit 1 }

$mode = if ($Force) { "EXECUTE" } else { "DRY RUN (add -Force to apply)" }
Write-Output "=== Network Repair ==="
Write-Output "Mode: $mode  |  Host: $env:COMPUTERNAME`n"

function Step($desc, [scriptblock]$act) {
    if ($Force) { try { & $act; Write-Output "  OK  : $desc" } catch { Write-Output "  [!] : $desc -> $($_.Exception.Message)" } }
    else { Write-Output "  WOULD: $desc" }
}

Step "flush DNS cache"                 { ipconfig /flushdns | Out-Null }
Step "release DHCP lease"              { ipconfig /release  | Out-Null }
Step "renew DHCP lease"                { ipconfig /renew    | Out-Null }
Step "clear ARP cache"                 { netsh interface ip delete arpcache | Out-Null }
Step "reset DNS client (register)"     { ipconfig /registerdns | Out-Null }

if (-not $SkipStackReset) {
    Write-Output "`n  -- stack reset (requires reboot to finish) --"
    Step "reset Winsock catalog"        { netsh winsock reset | Out-Null }
    Step "reset IPv4 stack"             { netsh int ip reset   | Out-Null }
    Step "reset IPv6 stack"             { netsh int ipv6 reset | Out-Null }
}

Write-Output "`n  -- bounce active adapter(s) --"
Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Virtual -eq $false } | ForEach-Object {
    $name = $_.Name
    Step "restart adapter '$name'" { Disable-NetAdapter -Name $name -Confirm:$false; Start-Sleep -Seconds 3; Enable-NetAdapter -Name $name -Confirm:$false }
}

Write-Output ""
if ($Force) {
    if (-not $SkipStackReset) { Write-Output "[!] Winsock/IP stack was reset — REBOOT to finish. Then verify with Get-NetworkDiagnostics.ps1." }
    else { Write-Output "Done. Verify with Get-NetworkDiagnostics.ps1." }
} else {
    Write-Output "Dry run complete. Re-run with -Force. Use -SkipStackReset for a no-reboot refresh."
}
