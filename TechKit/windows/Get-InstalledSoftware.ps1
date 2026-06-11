<#
.SYNOPSIS
    Inventory installed software from the registry (64-bit, 32-bit, and per-user).
.DESCRIPTION
    Read-only. Faster and more complete than Win32_Product (which is slow and can
    trigger MSI repairs - never use that). Useful for "what changed recently".
.PARAMETER Search
    Filter by name substring, e.g. -Search chrome
.PARAMETER SortByDate
    Sort by install date (newest first) instead of name - good for "it broke last week".
#>
[CmdletBinding()]
param([string]$Search, [switch]$SortByDate)

$paths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$apps = foreach ($p in $paths) {
    Get-ItemProperty $p -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and -not $_.SystemComponent } | ForEach-Object {
        $date = $null
        if ($_.InstallDate -match '^\d{8}$') { $date = [datetime]::ParseExact($_.InstallDate, 'yyyyMMdd', $null) }
        [PSCustomObject]@{
            Name      = $_.DisplayName
            Version   = $_.DisplayVersion
            Publisher = $_.Publisher
            Installed = $date
            Scope     = if ($p -like 'HKCU*') { 'user' } elseif ($p -like '*WOW6432*') { '32-bit' } else { '64-bit' }
        }
    }
}

$apps = $apps | Sort-Object Name, Version -Unique
if ($Search) { $apps = $apps | Where-Object Name -like "*$Search*" }
if ($SortByDate) { $apps = $apps | Sort-Object { if ($_.Installed) { $_.Installed } else { [datetime]::MinValue } } -Descending }

$suffix = if ($Search) { " matching '$Search'" } else { "" }
Write-Output ("{0} applications{1}:`n" -f $apps.Count, $suffix)
$apps | ForEach-Object {
    $d = if ($_.Installed) { $_.Installed.ToString('yyyy-MM-dd') } else { '          ' }
    Write-Output ("  {0}  {1,-7} {2,-45} {3,-18} {4}" -f $d, $_.Scope, ($_.Name.Substring(0,[math]::Min(45,$_.Name.Length))), $_.Version, $_.Publisher)
}
