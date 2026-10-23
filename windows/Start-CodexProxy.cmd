@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-CodexProxy.ps1" %*
set "launcher_result=%errorlevel%"
echo.
pause
exit /b %launcher_result%
