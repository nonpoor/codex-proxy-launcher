[CmdletBinding()]
param([string]$CodexPath = $env:CODEX_PROXY_CODEX_BIN, [string]$ProxyUrl = $env:HTTP_PROXY_URL,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$CodexArguments)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\ProxyRoute.ps1"
try {
    $codex = Get-CodexCommand $CodexPath
    $route = Select-ProxyRoute @(Resolve-ProxyRoute $ProxyUrl) -First
    Invoke-WithProxyRoute $route { & $codex @CodexArguments }
    exit $LASTEXITCODE
} catch {
    Write-Host 'CLI launch failed. Check CodexPath and proxy availability.' -ForegroundColor Red
    exit 1
}
