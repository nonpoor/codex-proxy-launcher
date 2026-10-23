@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Diagnose-CodexNetwork.ps1" %*
set "diagnostic_result=%errorlevel%"
echo.
pause
exit /b %diagnostic_result%
