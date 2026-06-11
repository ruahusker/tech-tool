$ErrorActionPreference = "Stop"

$InstallDir = Join-Path $env:USERPROFILE ".tech-utility\qwen-coder-tech-agent"
$LegacyInstallDir = Join-Path $env:USERPROFILE ".tech-utility\qwen-coder-codex"
$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
$ConfigTarget = Join-Path $CodexHome "qwen-coder.config.toml"
$LegacyConfigTarget = Join-Path $CodexHome "qwen-coder-old.config.toml"
$PidFile = Join-Path $InstallDir "run\llama-server.pid"
$LegacyPidFile = Join-Path $LegacyInstallDir "run\llama-server.pid"

Write-Host "This will uninstall the local Qwen Coder Tech Agent toolkit from this PC."
Write-Host ""
Write-Host "It will remove:"
Write-Host "  $InstallDir"
Write-Host "  $LegacyInstallDir"
Write-Host "  $ConfigTarget"
Write-Host "  $LegacyConfigTarget"
Write-Host ""
Write-Host "It will not remove your normal Qwen Code, Codex, shell, or model settings outside this toolkit."
Write-Host ""
$answer = Read-Host "Continue? [y/N]"

if ($answer -notin @("y", "Y", "yes", "YES")) {
    Write-Host "Uninstall cancelled."
    exit 0
}

if (Test-Path -LiteralPath $PidFile) {
    $oldPid = Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($oldPid) {
        Stop-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
    }
}

if (Test-Path -LiteralPath $LegacyPidFile) {
    $oldPid = Get-Content -LiteralPath $LegacyPidFile -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($oldPid) {
        Stop-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
    }
}

Get-CimInstance Win32_Process -Filter "name = 'llama-server.exe'" -ErrorAction SilentlyContinue |
    Where-Object { ($_.ExecutablePath -like "$InstallDir*") -or ($_.ExecutablePath -like "$LegacyInstallDir*") } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }

Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $LegacyInstallDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $ConfigTarget -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $LegacyConfigTarget -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Qwen Coder Tech Agent toolkit uninstalled."
Write-Host "Press Enter to close this window."
[void][Console]::ReadLine()
