[CmdletBinding()]
param(
    [string]$AppPath = $env:CODEX_PROXY_APP_BIN,
    [string]$ProxyUrl = $env:HTTP_PROXY_URL,
    [switch]$FirstRoute
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\ProxyRoute.ps1"

try {
    $app = Get-DesktopAppPath $AppPath
    $running = @(Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($app)) -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        Write-Host 'The desktop app is already running. Exit it manually before applying a new route.'
        exit 0
    }
    $route = Select-ProxyRoute @(Resolve-ProxyRoute $ProxyUrl) -First:$FirstRoute
    $summary = '{0} {1}' -f $route.Source, (Protect-ProxyUrl $route.Url)
    Write-Host "Startup HTTP probe passed: $summary"
    $launched = Invoke-WithProxyRoute $route {
        # Shell activation can reuse an existing process and lose our environment.
        Start-ProxyDesktopProcess $app
    }
    if (-not $launched) { throw 'The desktop process did not start.' }
    Write-LauncherEvent (Join-Path $PSScriptRoot '..\logs') "spawned pid=$($launched.Id) route=$summary"
    Write-Host "Desktop process started (PID $($launched.Id)). Run Diagnose-CodexNetwork.cmd to check WebSocket."
} catch {
    # Do not print exception URLs, credentials, or native application output.
    Write-Host 'Launch failed. Check the app path, proxy route and whether this package permits direct executable launch.' -ForegroundColor Red
    Write-Host 'Use -AppPath and -ProxyUrl for explicit paths; no system proxy or app files were changed.'
    exit 1
}
