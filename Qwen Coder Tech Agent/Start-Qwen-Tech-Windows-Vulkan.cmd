@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "QWEN_LLAMA_BACKEND=vulkan"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\install_and_launch_windows.ps1"
if errorlevel 1 pause
