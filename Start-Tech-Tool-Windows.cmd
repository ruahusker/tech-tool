@echo off
REM Tech Tool - Windows launcher. Double-click to start the app.
REM Extracts the bundled Node runtime (one-time) and starts the local UI server,
REM which opens your browser to the Tech Tool interface.
setlocal

set "DRIVE_ROOT=%~dp0"
set "UI_DIR=%DRIVE_ROOT%TechTool-UI"
set "RUNTIME_DIR=%UI_DIR%\runtime"
set "LOGFILE=%UI_DIR%\last-run-windows.log"
set "INSTALL_DIR=%USERPROFILE%\.tech-utility\qwen-coder-tech-agent"
set "NODE_HOME=%INSTALL_DIR%\node-ui"
set "NODE_SUB=node-v22.12.0-win-x64"
set "NODE_BIN=%NODE_HOME%\%NODE_SUB%\node.exe"

REM Start a fresh diagnostic log on the USB drive.
echo Tech Tool launch %DATE% %TIME% > "%LOGFILE%"
echo DRIVE_ROOT=%DRIVE_ROOT% >> "%LOGFILE%"
echo INSTALL_DIR=%INSTALL_DIR% >> "%LOGFILE%"
echo NODE_BIN=%NODE_BIN% >> "%LOGFILE%"

if not exist "%NODE_BIN%" (
    echo Setting up Tech Tool ^(one-time^)...
    echo [setup] extracting Node runtime >> "%LOGFILE%"
    if not exist "%NODE_HOME%" mkdir "%NODE_HOME%"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%RUNTIME_DIR%\node-v22.12.0-win-x64.zip' -DestinationPath '%NODE_HOME%' -Force" >> "%LOGFILE%" 2>&1
)

if not exist "%NODE_BIN%" (
    echo.
    echo   ERROR: could not set up the Node runtime. See:
    echo   %LOGFILE%
    echo.
    echo [error] NODE_BIN missing after extraction >> "%LOGFILE%"
    pause
    exit /b 1
)

cls
echo.
echo   Tech Tool is starting...
echo   Your web browser will open automatically.
echo   This first launch copies the AI model and can take a few minutes.
echo   Keep this window open while you work. Close it to quit.
echo.
echo   (A detailed log is being written to the USB drive:)
echo   %LOGFILE%
echo.

REM Tee node output to both the console and the USB log so problems are diagnosable.
"%NODE_BIN%" "%UI_DIR%\server.js" 2>&1 | "%NODE_BIN%" -e "process.stdin.pipe(require('fs').createWriteStream(process.argv[1],{flags:'a'})); process.stdin.pipe(process.stdout);" "%LOGFILE%"

echo.
echo Tech Tool has stopped. Log saved to %LOGFILE%
pause
