@echo off
REM Tech Tool - Windows launcher (IBM Granite model). Double-click to start.
REM Same as Start-Tech-Tool-Windows.cmd, but runs on the faster IBM Granite 4.0
REM H-Tiny model (a Mixture-of-Experts model that generates ~2.5x faster on
REM CPU-only machines than the default Qwen model). It just selects the model,
REM then hands off to the normal launcher, so any fixes there apply here too.
REM TECHTOOL_MODEL is set before CALL, so it is visible inside the called
REM launcher's setlocal scope and inherited by the Node process.
set "TECHTOOL_MODEL=granite"
call "%~dp0Start-Tech-Tool-Windows.cmd"
