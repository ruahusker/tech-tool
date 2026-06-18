@echo off
REM Tech Tool - Windows launcher. Double-click to start the app.
REM Extracts the bundled Node runtime (one-time) and starts the local UI server,
REM which opens your browser to the Tech Tool interface.
setlocal

REM ---- Model selection survives a UAC relaunch via the first argument. ----
REM The Granite wrapper sets TECHTOOL_MODEL in the environment before CALLing
REM this script; the elevated relaunch below passes it back in as %1 (a RunAs
REM relaunch starts with a fresh environment that would otherwise drop it).
if "%~2"=="elevated" set "TT_ELEVATED=1"
if not "%~1"=="" if /I not "%~1"=="default" set "TECHTOOL_MODEL=%~1"
set "TT_MODEL_ARG=%TECHTOOL_MODEL%"
if not defined TT_MODEL_ARG set "TT_MODEL_ARG=default"

REM ---- Self-elevate so admin repair tools (user cleanup, WU/SCCM/spooler
REM repair, Office/Adobe removal, etc.) can actually run. One UAC prompt at
REM launch. If the tech declines UAC, we keep running without admin so
REM read-only triage still works - admin-only tools will just report they
REM need elevation instead of failing silently.
if defined TT_ELEVATED goto :afterElevation
net session >nul 2>&1
if not errorlevel 1 goto :afterElevation
echo Requesting administrator privileges so all repair tools can run...
powershell -NoProfile -Command "try { Start-Process -FilePath '%~f0' -ArgumentList '%TT_MODEL_ARG%','elevated' -Verb RunAs } catch { exit 1 }"
if not errorlevel 1 exit /b
echo   UAC was declined - continuing without administrator rights.
echo   Admin-only tools (user cleanup, system repair) will be limited.
echo.
:afterElevation

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
