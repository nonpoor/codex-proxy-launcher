Set-StrictMode -Version 2.0

function Install-ProxyFiles([string]$SourceRoot, [string]$InstallDirectory) {
    $source = [IO.Path]::GetFullPath($SourceRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $destination = [IO.Path]::GetFullPath($InstallDirectory).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $files = @('ProxyRoute.ps1', 'Start-CodexProxy.ps1', 'Start-CodexProxy.cmd',
        'Diagnose-CodexNetwork.ps1', 'Diagnose-CodexNetwork.cmd', 'Start-CodexCLI.ps1',
        'InstallSupport.ps1', 'Install-CodexProxy.ps1')
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $source 'windows') $file) -PathType Leaf)) {
            throw 'The download is incomplete. Extract the entire release ZIP before installing.'
        }
    }
    $marker = Join-Path $destination '.codex-proxy-launcher.install'
    if ($source -ne $destination -and (Test-Path -LiteralPath $destination)) {
        $contents = @(Get-ChildItem -LiteralPath $destination -Force)
        if ($contents.Count -gt 0 -and
            (-not (Test-Path -LiteralPath $marker) -or (Get-Content -LiteralPath $marker -Raw).Trim() -ne 'Codex Proxy Launcher')) {
            throw 'The install directory contains unmanaged files. Choose an empty directory.'
        }
    }
    [void][IO.Directory]::CreateDirectory((Join-Path $destination 'windows'))
    if ($source -ne $destination) {
        foreach ($file in $files) {
            Copy-Item -LiteralPath (Join-Path (Join-Path $source 'windows') $file) `
                -Destination (Join-Path (Join-Path $destination 'windows') $file) -Force
        }
        foreach ($file in @('README.md', 'README.txt', 'LICENSE', 'NOTICE.md', 'VERSION')) {
            $path = Join-Path $source $file
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Copy-Item -LiteralPath $path -Destination (Join-Path $destination $file) -Force
            }
        }
        if (Test-Path -LiteralPath (Join-Path $source 'docs')) {
            [void][IO.Directory]::CreateDirectory((Join-Path $destination 'docs'))
            Get-ChildItem -LiteralPath (Join-Path $source 'docs') -Filter '*.md' |
                Copy-Item -Destination (Join-Path $destination 'docs') -Force
        }
    }
    Set-Content -LiteralPath $marker -Value 'Codex Proxy Launcher' -Encoding ASCII
    return $destination
}

function New-ProxyShortcuts([string]$InstallDirectory, [string]$DesktopDirectory,
    [string]$StartMenuDirectory) {
    $shell = New-Object -ComObject WScript.Shell
    $entries = @{
        'Codex Proxy.lnk' = 'Start-CodexProxy.cmd'
        'Codex Network Diagnosis.lnk' = 'Diagnose-CodexNetwork.cmd'
    }
    foreach ($directory in @($DesktopDirectory, $StartMenuDirectory)) {
        if (-not $directory) { continue }
        [void][IO.Directory]::CreateDirectory($directory)
        foreach ($name in $entries.Keys) {
            $target = Join-Path (Join-Path $InstallDirectory 'windows') $entries[$name]
            $linkPath = Join-Path $directory $name
            $link = $shell.CreateShortcut($linkPath)
            if ((Test-Path -LiteralPath $linkPath) -and $link.TargetPath -ne $target) {
                throw 'A shortcut with the same name belongs to another location; it was not overwritten.'
            }
            $link.TargetPath = $target
            $link.WorkingDirectory = $InstallDirectory
            $link.Description = 'Codex Proxy Launcher'
            $link.Save()
        }
    }
}
