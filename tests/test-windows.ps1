# No Pester dependency, no real network, no registry writes or desktop launches.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../windows/ProxyRoute.ps1"
$script:Assertions = 0
function Assert-True($Condition, [string]$Message) {
    $script:Assertions++
    if (-not $Condition) { throw "Assertion failed: $Message" }
}
function Assert-Equal($Expected, $Actual, [string]$Message) {
    Assert-True ($Expected -ceq $Actual) "$Message (expected=$Expected, actual=$Actual)"
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $thrown = $false
    try { & $Action | Out-Null } catch { $thrown = $true }
    Assert-True $thrown $Message
}

# Parse every script with the actual PowerShell parser before running behavior.
foreach ($file in @(Get-ChildItem "$PSScriptRoot/../windows", $PSScriptRoot -Filter '*.ps1')) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    Assert-Equal 0 $errors.Count "Parse $($file.Name)"
}

Assert-True (Test-ProxyUrl 'http://127.0.0.1:12345') 'arbitrary proxy port'
Assert-True (Test-ProxyUrl 'http://[::1]:12345') 'IPv6 proxy'
Assert-True (Test-ProxyUrl 'http://alice:secret@localhost:8888') 'proxy credentials'
foreach ($bad in @('socks5://localhost:8888', 'http://localhost:70000', 'not-a-url',
    "http://localhost:88`n", 'http://localhost:88/path', 'http://localhost:88?token=secret')) {
    Assert-True (-not (Test-ProxyUrl $bad)) 'reject malformed or unsupported URL'
}
Assert-Equal 'http://<redacted>@localhost:8888' (Protect-ProxyUrl 'http://alice:secret@localhost:8888') 'redact user info'

$parsed = @(ConvertFrom-WindowsProxyServer 'http=localhost:1234;https=localhost:5678;socks=localhost:9999')
Assert-Equal 2 $parsed.Count 'only HTTP proxy entries'
Assert-Equal 'http://localhost:5678' $parsed[0].Url 'HTTPS proxy preference'
Assert-Equal 'http://localhost:1234' $parsed[1].Url 'HTTP proxy fallback'
$parsed = @(ConvertFrom-WindowsProxyServer 'localhost:4321')
Assert-Equal 'http://localhost:4321' $parsed[0].Url 'single Windows proxy entry'

# Exercise the Windows discovery adapter with fake registry/process/socket data.
function Get-ItemProperty { [pscustomobject]@{ ProxyEnable = 1; ProxyServer = 'localhost:4567' } }
function Get-Process {
    @([pscustomobject]@{Id=100;ProcessName='FlClash'},
      [pscustomobject]@{Id=200;ProcessName='postgres'})
}
function Get-NetTCPConnection {
    @([pscustomobject]@{OwningProcess=100;LocalAddress='0.0.0.0';LocalPort=4567},
      [pscustomobject]@{OwningProcess=100;LocalAddress='::1';LocalPort=4568},
      [pscustomobject]@{OwningProcess=200;LocalAddress='127.0.0.1';LocalPort=5432},
      [pscustomobject]@{OwningProcess=100;LocalAddress='192.168.1.2';LocalPort=9999})
}
$candidates = @(Get-WindowsProxyCandidates)
Assert-Equal 3 $candidates.Count 'discover system and owned loopback listeners only'
Assert-Equal 'http://127.0.0.1:4567' $candidates[1].Url 'wildcard normalized to loopback'
Assert-Equal 'http://[::1]:4568' $candidates[2].Url 'IPv6 listener'

$script:DirectWorks = $true
$script:WorkingProxies = @()
$script:ProbeCalls = @()
function Test-ProxyRoute([string]$Url = '') {
    $script:ProbeCalls += $Url
    if (-not $Url) { return $script:DirectWorks }
    return $Url -in $script:WorkingProxies
}
$routes = @(Resolve-ProxyRoute -ProxyUrl '')
Assert-Equal 1 $routes.Count 'one system route'
Assert-Equal 'system' $routes[0].Mode 'prefer system/TUN'
Assert-Equal 1 $script:ProbeCalls.Count 'system success skips discovery'
$script:DirectWorks = $false
$script:WorkingProxies = @('http://localhost:4567', 'http://127.0.0.1:4567')
$routes = @(Resolve-ProxyRoute -ProxyUrl '')
Assert-Equal 2 $routes.Count 'validate candidates'
Assert-Equal 'explicit' $routes[0].Mode 'explicit route'
$route = Resolve-ProxyRoute -ProxyUrl 'http://localhost:4567'
Assert-Equal 'explicit override' $route.Source 'authoritative override'
$script:DirectWorks = $true
Assert-Throws { Resolve-ProxyRoute -ProxyUrl 'http://localhost:6553' } 'bad override must not fall back'
$script:DirectWorks = $false
$script:WorkingProxies = @()
Assert-Throws { Resolve-ProxyRoute -ProxyUrl '' } 'no route must fail'

function Read-Host { '2' }
Assert-Equal $routes[1].Url (Select-ProxyRoute $routes).Url 'route selection'
Assert-Equal $routes[0].Url (Select-ProxyRoute $routes -First).Url 'noninteractive first route'
function Read-Host { '' }
Assert-Throws { Select-ProxyRoute $routes } 'cancel selection'

$explicit = [pscustomobject]@{Mode='explicit';Source='test';Url='http://localhost:4567'}
$system = [pscustomobject]@{Mode='system';Source='system/TUN';Url=''}
$testDir = Join-Path ([IO.Path]::GetTempPath()) ('codex-proxy-test-' + [Guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($testDir)
$names = @(Get-ProxyEnvironmentNames) + @('GIT_CONFIG_COUNT', 'GIT_CONFIG_PARAMETERS',
    'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0', 'GIT_CONFIG_KEY_1', 'GIT_CONFIG_VALUE_1',
    'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM')
$saved = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    $env:HTTP_PROXY = 'http://old.invalid:9999'
    $env:ALL_PROXY = 'socks5://old.invalid:9999'
    $env:WS_PROXY = 'http://old.invalid:9999'
    $env:GIT_CONFIG_COUNT = '1'
    $env:GIT_CONFIG_KEY_0 = 'user.name'
    $env:GIT_CONFIG_VALUE_0 = 'test-user'
    $env:GIT_CONFIG_PARAMETERS = $null
    $env:GIT_CONFIG_GLOBAL = Join-Path $testDir 'gitconfig'
    $env:GIT_CONFIG_NOSYSTEM = '1'
    Set-Content -LiteralPath $env:GIT_CONFIG_GLOBAL -Value "[http]`n    proxy = http://stale.invalid:9999"

    Invoke-WithProxyRoute $explicit {
        Assert-Equal $explicit.Url $env:HTTPS_PROXY 'inject HTTPS proxy'
        Assert-True (-not $env:ALL_PROXY -and -not $env:WS_PROXY) 'clear competing variables'
        Assert-Equal '2' $env:GIT_CONFIG_COUNT 'append Git config'
        Assert-Equal 'test-user' $env:GIT_CONFIG_VALUE_0 'preserve other Git config'
        $actual = & git config --get-urlmatch http.proxy https://github.com/openai/codex.git
        Assert-Equal $explicit.Url $actual 'effective Git proxy matches explicit route'
    }
    Assert-Equal 'http://old.invalid:9999' $env:HTTP_PROXY 'restore caller environment'
    Assert-Equal '1' $env:GIT_CONFIG_COUNT 'restore caller Git config'
    Assert-True (-not $env:GIT_CONFIG_KEY_1) 'remove temporary Git entry'
    Invoke-WithProxyRoute $system {
        Assert-True (-not $env:HTTP_PROXY -and -not $env:ALL_PROXY) 'system clears stale proxies'
        $actual = & git config --get-urlmatch http.proxy https://github.com/openai/codex.git
        Assert-True (-not $actual) 'system overrides stale global Git proxy on PS5 and PS7'
    }
    Assert-Throws { Invoke-WithProxyRoute $explicit { throw 'fake child error' } } 'child failure propagates'
    Assert-Equal 'http://old.invalid:9999' $env:HTTP_PROXY 'restore on failure'

    $healthy = '{"checks":{"network.provider_reachability":{"status":"ok"},"network.websocket_reachability":{"status":"ok"}}}' | ConvertFrom-Json
    Assert-True (Get-CodexNetworkResult $healthy).Success 'network-only doctor verdict'
    $healthy.checks.'network.provider_reachability'.status = 'warning'
    Assert-True (-not (Get-CodexNetworkResult $healthy).Success) 'warning is not an all-clear'
    Assert-Throws { Get-CodexNetworkResult ('{}' | ConvertFrom-Json) } 'missing checks fail'

    $fakeApp = Join-Path $testDir 'Desktop with spaces.exe'
    Set-Content -LiteralPath $fakeApp -Value ''
    Assert-Equal $fakeApp (Get-DesktopAppPath $fakeApp) 'explicit path with spaces'
    Assert-Throws { Get-DesktopAppPath (Join-Path $testDir 'missing.exe') } 'bad app path fails'
    $fakeCodex = Join-Path $testDir 'codex.exe'
    Set-Content -LiteralPath $fakeCodex -Value ''
    Assert-Equal $fakeCodex (Get-CodexCommand $fakeCodex) 'explicit CLI path'

    $logDir = Join-Path $testDir 'logs'
    Write-LauncherEvent $logDir ('route=' + (Protect-ProxyUrl 'http://alice:secret@localhost:4567'))
    $logFile = Join-Path $logDir 'windows-launcher.log'
    Assert-True ((Get-Content $logFile -Raw) -notmatch 'secret|alice') 'no credentials in log'
    [IO.File]::WriteAllText($logFile, ('x' * 1MB))
    Write-LauncherEvent $logDir 'next launch'
    Assert-True (Test-Path "$logFile.1") 'rotate log'

    # Run entry scripts in a separate PowerShell process with a fake route and
    # child executable, so orchestration, JSON parsing and exit codes are tested.
    $entryDir = Join-Path $testDir 'windows'
    [void][IO.Directory]::CreateDirectory($entryDir)
    Copy-Item "$PSScriptRoot/../windows/ProxyRoute.ps1" $entryDir
    Copy-Item "$PSScriptRoot/../windows/Start-CodexProxy.ps1" $entryDir
    Copy-Item "$PSScriptRoot/../windows/Diagnose-CodexNetwork.ps1" $entryDir
    $stubs = @'
function Resolve-ProxyRoute([string]$ProxyUrl) {
    if ($ProxyUrl -eq 'http://bad.invalid:88') { throw 'fake unreachable route' }
    [pscustomobject]@{ Mode='explicit'; Source='test route'; Url='http://localhost:4567' }
}
function Get-Process { @() }
function Start-ProxyDesktopProcess([string]$AppPath) {
    Set-Content (Join-Path $PSScriptRoot 'captured-env.txt') $env:HTTPS_PROXY
    [pscustomobject]@{Id=1234}
}
'@
    Add-Content (Join-Path $entryDir 'ProxyRoute.ps1') $stubs
    $hostExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $output = & $hostExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $entryDir 'Start-CodexProxy.ps1') -AppPath $fakeApp 2>&1
    Assert-Equal 0 $LASTEXITCODE 'desktop entry succeeds with fake process'
    Assert-Equal $explicit.Url (Get-Content (Join-Path $entryDir 'captured-env.txt')) 'desktop inherits selected route'
    $output = & $hostExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $entryDir 'Start-CodexProxy.ps1') -AppPath $fakeApp -ProxyUrl 'http://bad.invalid:88' 2>&1
    Assert-Equal 1 $LASTEXITCODE 'bad route prevents launch entry success'

    $fakeDoctor = Join-Path $testDir 'fake-doctor.ps1'
    Set-Content $fakeDoctor @'
Write-Output '{"checks":{"network.provider_reachability":{"status":"ok"},"network.websocket_reachability":{"status":"ok","details":{"handshake result":"HTTP 101 Switching Protocols"}}}}'
exit 1
'@
    $output = & $hostExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $entryDir 'Diagnose-CodexNetwork.ps1') -CodexPath $fakeDoctor 2>&1
    Assert-Equal 0 $LASTEXITCODE 'healthy network wins over unrelated doctor exit'
    Assert-True (($output -join "`n") -match 'HTTP 101') 'entry prints handshake'
    Set-Content $fakeDoctor "Write-Output '{}'"
    $output = & $hostExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $entryDir 'Diagnose-CodexNetwork.ps1') -CodexPath $fakeDoctor 2>&1
    Assert-Equal 1 $LASTEXITCODE 'malformed doctor report fails entry'
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    Remove-Item -LiteralPath $testDir -Recurse -Force
}
Write-Host "Windows proxy tests: OK ($script:Assertions assertions)"
# GitHub's -Command wrapper propagates LASTEXITCODE from the deliberate final
# failure case. All assertions above must finish before this success is emitted.
exit 0
