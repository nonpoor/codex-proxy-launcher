# Compatible with Windows PowerShell 5.1 and PowerShell 7. No profile changes.
Set-StrictMode -Version 2.0

function Get-ProxyEnvironmentNames {
    @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'WS_PROXY', 'WSS_PROXY', 'NO_PROXY',
      'http_proxy', 'https_proxy', 'all_proxy', 'ws_proxy', 'wss_proxy', 'no_proxy',
      'HTTP_PROXY_URL', 'NO_PROXY_HOSTS')
}

function Protect-ProxyUrl([string]$Url) {
    if ($Url -match '^([^:]+://).*@([^@]+)$') {
        return $Matches[1] + '<redacted>@' + $Matches[2]
    }
    return $Url
}

function Test-ProxyUrl([string]$Url) {
    $parsed = $null
    if ($Url -match '[\s]' -or -not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$parsed)) {
        return $false
    }
    # HTTP CONNECT carries HTTPS/WSS. This is the proxy's scheme, not the target's.
    return $parsed.Scheme -eq 'http' -and $parsed.Host -ne '' -and
        $parsed.Port -ge 1 -and $parsed.Port -le 65535 -and
        $parsed.AbsolutePath -eq '/' -and $parsed.Query -eq '' -and $parsed.Fragment -eq ''
}

function Test-ProxyRoute([string]$Url = '') {
    $request = [System.Net.HttpWebRequest]::Create('https://api.openai.com/v1/models')
    $request.Timeout = 8000
    $request.ReadWriteTimeout = 8000
    $request.AllowAutoRedirect = $false
    # Never inherit WinINET/environment proxy settings in the system/TUN test.
    $request.Proxy = $null
    if ($Url) {
        if (-not (Test-ProxyUrl $Url)) { return $false }
        $uri = [Uri]$Url
        $proxy = New-Object System.Net.WebProxy($uri.GetLeftPart([UriPartial]::Authority))
        if ($uri.UserInfo) {
            $parts = $uri.UserInfo.Split(':', 2)
            $password = ''
            if ($parts.Count -gt 1) { $password = [Uri]::UnescapeDataString($parts[1]) }
            $proxy.Credentials = New-Object System.Net.NetworkCredential(
                [Uri]::UnescapeDataString($parts[0]), $password)
        }
        $request.Proxy = $proxy
    }
    $response = $null
    try {
        $response = $request.GetResponse()
    } catch [System.Net.WebException] {
        $response = $_.Exception.Response
    } catch {
        return $false
    }
    if ($null -eq $response) { return $false }
    try {
        $code = [int]$response.StatusCode
        return $code -ge 200 -and $code -lt 500 -and $code -ne 407
    } finally {
        $response.Close()
    }
}

function ConvertFrom-WindowsProxyServer([string]$Server) {
    $entries = @{}
    foreach ($part in $Server.Split(';')) {
        if ($part -match '^(https|http)=(.+)$') { $entries[$Matches[1]] = $Matches[2] }
        elseif ($part -and $part -notmatch '=') { $entries['all'] = $part }
    }
    foreach ($scheme in @('https', 'http', 'all')) {
        if (-not $entries.ContainsKey($scheme)) { continue }
        $url = $entries[$scheme]
        if ($url -notmatch '^[a-z]+://') { $url = 'http://' + $url }
        if (Test-ProxyUrl $url) {
            [pscustomobject]@{ Source = 'Windows system proxy'; Url = $url }
        }
    }
}

function Get-WindowsProxyCandidates {
    $settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' `
        -ErrorAction SilentlyContinue
    if ($settings -and $settings.PSObject.Properties['ProxyEnable'] -and
        $settings.ProxyEnable -eq 1 -and $settings.PSObject.Properties['ProxyServer']) {
        ConvertFrom-WindowsProxyServer $settings.ProxyServer
    }
    # Discover process-owned listeners, never assume a default Clash port.
    $owners = @{}
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($process.ProcessName -match '(?i)flclash|mihomo|clash|shadowrocket') {
            $owners[[int]$process.Id] = $process.ProcessName
        }
    }
    if ($owners.Count -eq 0) { return }
    foreach ($listener in @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue)) {
        $owner = [int]$listener.OwningProcess
        if (-not $owners.ContainsKey($owner)) { continue }
        $hostName = switch ($listener.LocalAddress) {
            '127.0.0.1' { '127.0.0.1' }
            '0.0.0.0'   { '127.0.0.1' }
            '::'        { '127.0.0.1' }
            '::1'       { '[::1]' }
            default    { $null }
        }
        if ($hostName) {
            [pscustomobject]@{
                Source = $owners[$owner]
                Url = 'http://{0}:{1}' -f $hostName, $listener.LocalPort
            }
        }
    }
}

function Resolve-ProxyRoute([string]$ProxyUrl = $env:HTTP_PROXY_URL) {
    if ($ProxyUrl) {
        if (-not (Test-ProxyUrl $ProxyUrl) -or -not (Test-ProxyRoute $ProxyUrl)) {
            throw 'Explicit HTTP proxy is invalid or unreachable; no fallback was attempted.'
        }
        return [pscustomobject]@{ Mode = 'explicit'; Source = 'explicit override'; Url = $ProxyUrl }
    }
    if (Test-ProxyRoute) {
        return [pscustomobject]@{ Mode = 'system'; Source = 'system/TUN'; Url = '' }
    }
    $seen = @{}
    $routes = @()
    foreach ($candidate in @(Get-WindowsProxyCandidates)) {
        if ($seen.ContainsKey($candidate.Url)) { continue }
        $seen[$candidate.Url] = $true
        if (Test-ProxyRoute $candidate.Url) {
            $routes += [pscustomobject]@{
                Mode = 'explicit'; Source = $candidate.Source; Url = $candidate.Url
            }
        }
    }
    if ($routes.Count -eq 0) {
        throw 'No usable system/TUN or HTTP proxy route. Start your proxy client and retry.'
    }
    return $routes
}

function Select-ProxyRoute($Routes, [switch]$First) {
    $items = @($Routes)
    if ($items.Count -eq 0) { throw 'No route was supplied.' }
    if ($items.Count -eq 1 -or $First) { return $items[0] }
    for ($i = 0; $i -lt $items.Count; $i++) {
        Write-Host ('[{0}] {1} {2}' -f ($i + 1), $items[$i].Source, (Protect-ProxyUrl $items[$i].Url))
    }
    $choice = Read-Host 'Choose a route number (Enter cancels)'
    $number = 0
    if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $items.Count) {
        throw 'Route selection cancelled.'
    }
    return $items[$number - 1]
}

function Set-ProxyRouteEnvironment($Route, [switch]$Git) {
    if ($Route.Mode -notin @('system', 'explicit')) { throw 'Unknown route mode.' }
    if ($Route.Mode -eq 'explicit' -and -not (Test-ProxyUrl $Route.Url)) { throw 'Invalid proxy URL.' }
    $bypass = $env:NO_PROXY_HOSTS
    if (-not $bypass) { $bypass = 'localhost,127.0.0.1,::1' }
    # Validate before changing any state.
    $count = 0
    if ($Git -and $env:GIT_CONFIG_COUNT -and
        (-not [int]::TryParse($env:GIT_CONFIG_COUNT, [ref]$count) -or $count -lt 0)) {
        throw 'Invalid GIT_CONFIG_COUNT.'
    }
    foreach ($name in Get-ProxyEnvironmentNames) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    if ($Route.Mode -eq 'explicit') {
        foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy')) {
            [Environment]::SetEnvironmentVariable($name, $Route.Url, 'Process')
        }
        $env:NO_PROXY = $bypass
        # Environment variable names are case-insensitive on Windows.
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { $env:no_proxy = $bypass }
    }
    if ($Git) {
        $gitProxy = ''
        if ($Route.Mode -eq 'explicit') { $gitProxy = $Route.Url }
        [Environment]::SetEnvironmentVariable("GIT_CONFIG_KEY_$count", 'http.proxy', 'Process')
        # PS 5.1 removes empty environment values. Use the config parameter
        # syntax to preserve http.proxy='' for system/TUN on that runtime.
        if ($gitProxy) {
            [Environment]::SetEnvironmentVariable("GIT_CONFIG_VALUE_$count", $gitProxy, 'Process')
            $env:GIT_CONFIG_COUNT = [string]($count + 1)
        } else {
            [Environment]::SetEnvironmentVariable("GIT_CONFIG_KEY_$count", $null, 'Process')
            $env:GIT_CONFIG_PARAMETERS = ($env:GIT_CONFIG_PARAMETERS + " 'http.proxy='").Trim()
        }
    }
}

function Invoke-WithProxyRoute($Route, [scriptblock]$Action) {
    $names = @(Get-ProxyEnvironmentNames) + @('GIT_CONFIG_COUNT', 'GIT_CONFIG_PARAMETERS')
    $count = 0
    if ($env:GIT_CONFIG_COUNT -and -not [int]::TryParse($env:GIT_CONFIG_COUNT, [ref]$count)) {
        throw 'Invalid GIT_CONFIG_COUNT.'
    }
    $names += @("GIT_CONFIG_KEY_$count", "GIT_CONFIG_VALUE_$count")
    $saved = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    try {
        Set-ProxyRouteEnvironment $Route -Git
        & $Action
    } finally {
        foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    }
}

function Get-DesktopAppPath([string]$AppPath = $env:CODEX_PROXY_APP_BIN) {
    if ($AppPath) {
        if (-not (Test-Path -LiteralPath $AppPath -PathType Leaf) -or
            [IO.Path]::GetExtension($AppPath) -ne '.exe') { throw 'AppPath must point to an existing desktop .exe.' }
        return (Get-Item -LiteralPath $AppPath).FullName
    }
    $candidates = @()
    foreach ($base in @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $base) { continue }
        foreach ($relative in @('Programs\Codex\Codex.exe', 'Programs\ChatGPT\ChatGPT.exe',
            'Codex\Codex.exe', 'ChatGPT\ChatGPT.exe')) {
            $candidates += Join-Path $base $relative
        }
    }
    if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
        foreach ($package in @(Get-AppxPackage -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)OpenAI.*(Codex|ChatGPT)|(Codex|ChatGPT).*OpenAI' })) {
            # Read the registered manifest instead of guessing a WindowsApps path.
            $manifestPath = Join-Path $package.InstallLocation 'AppxManifest.xml'
            if (-not (Test-Path -LiteralPath $manifestPath)) { continue }
            [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
            foreach ($application in @($manifest.Package.Applications.Application)) {
                $executable = $application.GetAttribute('Executable')
                if ($executable -match '(?i)(Codex|ChatGPT)\.exe$') {
                    $candidates += Join-Path $package.InstallLocation $executable
                }
            }
        }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Get-Item -LiteralPath $candidate).FullName }
    }
    throw 'Desktop app not found. Install Codex/ChatGPT, or pass -AppPath with its executable path.'
}

function Get-CodexCommand([string]$CodexPath = $env:CODEX_PROXY_CODEX_BIN, [string]$AppPath = '') {
    if ($CodexPath) {
        if (-not (Test-Path -LiteralPath $CodexPath -PathType Leaf)) { throw 'CodexPath does not exist.' }
        return (Get-Item -LiteralPath $CodexPath).FullName
    }
    if (-not $AppPath) {
        try { $AppPath = Get-DesktopAppPath } catch { $AppPath = '' }
    }
    if ($AppPath) {
        $appDir = Split-Path $AppPath -Parent
        foreach ($relative in @('resources\codex.exe', 'resources\codex-cli\bin\codex.exe',
            'resources\codex-cli\codex.exe', 'resources\codex\codex.exe')) {
            $candidate = Join-Path $appDir $relative
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    foreach ($name in @('codex.exe', 'codex.cmd')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }
    throw 'Codex CLI not found. Pass -CodexPath or install the CLI separately.'
}

function Get-CodexNetworkResult($Report) {
    if (-not $Report -or -not $Report.PSObject.Properties['checks']) { throw 'Doctor returned no checks.' }
    $http = $Report.checks.PSObject.Properties['network.provider_reachability']
    $ws = $Report.checks.PSObject.Properties['network.websocket_reachability']
    if (-not $http -or -not $ws) { throw 'Doctor did not return the required network checks.' }
    return [pscustomobject]@{
        Http = $http.Value; WebSocket = $ws.Value
        Success = ($http.Value.status -eq 'ok' -and $ws.Value.status -eq 'ok')
    }
}

function Start-ProxyDesktopProcess([string]$AppPath) {
    # Direct process creation snapshots this environment before it is restored.
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $AppPath
    $start.Arguments = '--disable-quic'
    $start.WorkingDirectory = Split-Path $AppPath -Parent
    $start.UseShellExecute = $false
    return [System.Diagnostics.Process]::Start($start)
}

function Write-LauncherEvent([string]$LogDirectory, [string]$Message) {
    [void][IO.Directory]::CreateDirectory($LogDirectory)
    $file = Join-Path $LogDirectory 'windows-launcher.log'
    if ((Test-Path -LiteralPath $file) -and (Get-Item -LiteralPath $file).Length -ge 1MB) {
        for ($i = 3; $i -ge 1; $i--) {
            $old = $file
            if ($i -gt 1) { $old = "$file.$($i - 1)" }
            if (Test-Path -LiteralPath $old) { Move-Item -LiteralPath $old -Destination "$file.$i" -Force }
        }
    }
    $safe = (Protect-ProxyUrl $Message) -replace '[\r\n\t]', ' '
    Add-Content -LiteralPath $file -Encoding UTF8 -Value ('[{0}] {1}' -f (Get-Date -Format 's'), $safe)
}
