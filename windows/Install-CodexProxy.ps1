[CmdletBinding()]
param(
    [string]$SourceRoot = '',
    [string]$InstallDirectory = '',
    [switch]$NoShortcuts
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\InstallSupport.ps1"
try {
    # Windows PowerShell 5.1 can evaluate parameter defaults before it sets
    # PSScriptRoot for a -File invocation. Resolve defaults in the script body.
    if (-not $SourceRoot) { $SourceRoot = Split-Path $PSScriptRoot -Parent }
    if (-not $InstallDirectory) {
        if (-not $env:LOCALAPPDATA) { throw 'A user-local application directory is required.' }
        $InstallDirectory = Join-Path $env:LOCALAPPDATA 'Programs\CodexProxyLauncher'
    }
    $installed = Install-ProxyFiles $SourceRoot $InstallDirectory
    if (-not $NoShortcuts) {
        $desktop = [Environment]::GetFolderPath('DesktopDirectory')
        $menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Codex Proxy Launcher'
        New-ProxyShortcuts $installed $desktop $menu
        Write-Host 'Installed. Use the Codex Proxy shortcut on your desktop or in the Start menu.'
        Write-Host 'Start your proxy client first, then exit any existing Codex/ChatGPT process.'
    }
    Write-Host "Installed files: $installed"
    exit 0
} catch {
    Write-Host 'Installation failed. Extract the complete ZIP and choose an empty install folder or a previous managed installation.' -ForegroundColor Red
    Write-Host 'If shortcut creation is blocked by device policy, run with -NoShortcuts and use windows\Start-CodexProxy.cmd.'
    exit 1
}
