@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\Install-CodexProxy.ps1" %*
set "install_result=%errorlevel%"
echo.
pause
exit /b %install_result%
