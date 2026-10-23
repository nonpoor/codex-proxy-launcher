[CmdletBinding()]
param([string]$CodexPath = $env:CODEX_PROXY_CODEX_BIN, [string]$ProxyUrl = $env:HTTP_PROXY_URL)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\ProxyRoute.ps1"

try {
    $codex = Get-CodexCommand $CodexPath
    $route = Select-ProxyRoute @(Resolve-ProxyRoute $ProxyUrl) -First
    Write-Host ('Route (first validated route): {0} {1}' -f $route.Source, (Protect-ProxyUrl $route.Url))
    $report = Invoke-WithProxyRoute $route {
        if (Get-Command git -ErrorAction SilentlyContinue) {
            $effective = & git config --get-urlmatch http.proxy https://github.com/openai/codex.git
            $expected = ''
            if ($route.Mode -eq 'explicit') { $expected = $route.Url }
            if (($effective -join '') -ne $expected) { throw 'Git proxy differs from selected route.' }
        }
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = & $codex doctor --json 2>$null
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        # A nonzero doctor exit can be caused by unrelated local checks.
        ($raw -join "`n") | ConvertFrom-Json
    }
    $result = Get-CodexNetworkResult $report
    Write-Host ('HTTP: {0}; WebSocket: {1}' -f $result.Http.status, $result.WebSocket.status)
    if ($result.WebSocket.PSObject.Properties['details']) {
        $handshake = $result.WebSocket.details.PSObject.Properties['handshake result']
        if ($handshake) { Write-Host ('Handshake: {0}' -f $handshake.Value) }
    }
    if (-not $result.Success) {
        Write-Host 'At least one required network check failed.' -ForegroundColor Red
        exit 1
    }
    Write-Host 'HTTP and Responses WebSocket checks passed at this time.'
    exit 0
} catch {
    Write-Host 'Diagnosis failed. Check CodexPath, proxy availability and support for codex doctor --json.' -ForegroundColor Red
    exit 1
}
