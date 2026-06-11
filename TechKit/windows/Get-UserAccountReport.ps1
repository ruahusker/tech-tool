<#
.SYNOPSIS
    Local user inventory: status, last logon, password age, admin membership, profile sizes.
.DESCRIPTION
    Read-only. Run before any account cleanup (this is the reconnaissance step for
    Remove-InactiveUsers.ps1) or when auditing who can access a machine.
.PARAMETER SkipProfileSizes
    Skip measuring C:\Users folder sizes (the slowest part).
#>
[CmdletBinding()]
param([switch]$SkipProfileSizes)

Write-Output "=== LOCAL USERS ==="
$admins = @()
try { $admins = (Get-LocalGroupMember Administrators -ErrorAction Stop).Name } catch {}
Get-LocalUser | Sort-Object Enabled -Descending | ForEach-Object {
    $isAdmin = ($admins -like "*\$($_.Name)") -or ($admins -contains $_.Name)
    $last = if ($_.LastLogon) { $_.LastLogon.ToString("yyyy-MM-dd") } else { "never" }
    $pwdAge = if ($_.PasswordLastSet) { [int]((Get-Date) - $_.PasswordLastSet).TotalDays } else { "-" }
    Write-Output ("  {0,-22} Enabled={1,-5} LastLogon={2,-10} PwdAge={3,-5} Admin={4}" -f $_.Name, $_.Enabled, $last, $pwdAge, $isAdmin)
}
Write-Output "  Note: LastLogon covers interactive logons on THIS machine; domain accounts are not listed here."

Write-Output "`n=== CURRENTLY LOGGED ON ==="
$q = & quser 2>$null
if ($q) { $q | ForEach-Object { Write-Output "  $_" } } else { & query user 2>$null | ForEach-Object { Write-Output "  $_" }; if (-not $?) { Write-Output "  (quser unavailable)" } }

Write-Output "`n=== PROFILE FOLDERS ==="
$profiles = Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special }
foreach ($p in $profiles) {
    $name = Split-Path $p.LocalPath -Leaf
    $size = ""
    if (-not $SkipProfileSizes -and (Test-Path $p.LocalPath)) {
        try {
            $bytes = (Get-ChildItem $p.LocalPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            $size = "{0,8:N1} GB" -f ($bytes/1GB)
        } catch { $size = "   (n/a)" }
    }
    $loaded = if ($p.Loaded) { "loaded " } else { "       " }
    Write-Output ("  {0} {1,-22} {2}  {3}" -f $loaded, $name, $size, $p.LocalPath)
}
Write-Output "  ('loaded' = registry hive in use right now, i.e. logged on or service running as that user)"

Write-Output "`n=== ADMINISTRATORS GROUP ==="
if ($admins) { $admins | ForEach-Object { Write-Output "  $_" } }
else { & net localgroup Administrators 2>$null | Select-Object -Skip 6 | Where-Object { $_ -and $_ -notmatch 'command completed' } | ForEach-Object { Write-Output "  $_" } }
