#!/usr/bin/env python3
"""Verify the downloadable ZIPs and install from an extracted Windows package."""
import argparse
import hashlib
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--powershell', default=shutil.which('pwsh') or shutil.which('powershell'))
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='codex-release-') as temporary:
        temp = Path(temporary)
        output = temp / 'packages'
        subprocess.run([sys.executable, str(ROOT / 'scripts/build-release.py'), '1.0.0',
                        '--output', str(output)], check=True, capture_output=True)
        for platform in ('windows', 'macos'):
            folder = f'codex-proxy-launcher-1.0.0-{platform}'
            archive = output / f'{folder}.zip'
            with zipfile.ZipFile(archive) as zf:
                assert zf.testzip() is None
                names = {name.removeprefix(folder + '/') for name in zf.namelist()}
                assert {'README.md', 'README.txt', 'LICENSE', 'NOTICE.md', 'VERSION'} <= names
                assert all(not set(Path(name).parts) & {'.git', 'logs', 'assets', 'tests'} for name in names)
                if platform == 'windows':
                    assert {'Install-Windows.cmd', 'windows/Install-CodexProxy.ps1',
                            'windows/InstallSupport.ps1', 'windows/ProxyRoute.ps1',
                            'windows/Start-CodexProxy.cmd'} <= names
                    for name in zf.namelist():
                        if name.endswith('.cmd'):
                            assert b'\n' not in zf.read(name).replace(b'\r\n', b'')
                    zf.extractall(temp / 'extracted')
                else:
                    entry = zf.getinfo(folder + '/Codex Proxy.app/Contents/MacOS/codex-proxy-launcher')
                    assert (entry.external_attr >> 16) & stat.S_IXUSR
                    assert {'lib/proxy-route.zsh', 'lib/codex-runtime.zsh',
                            'diagnose-codex-network.command'} <= names
            expected = hashlib.sha256(archive.read_bytes()).hexdigest()
            assert f'{expected}  {archive.name}' in (output / 'SHA256SUMS.txt').read_text()
        if not args.powershell:
            raise RuntimeError('PowerShell is required to smoke-test the extracted installer')
        source = temp / 'extracted/codex-proxy-launcher-1.0.0-windows'
        installed = temp / 'installed with spaces'
        result = subprocess.run([args.powershell, '-NoLogo', '-NoProfile', '-ExecutionPolicy',
                                 'Bypass', '-File', str(source / 'windows/Install-CodexProxy.ps1'),
                                 '-InstallDirectory', str(installed), '-NoShortcuts'],
                                capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        assert (installed / 'windows/Start-CodexProxy.cmd').is_file()
        assert (installed / '.codex-proxy-launcher.install').is_file()
        assert not (installed / 'logs').exists()
    print('Release ZIP validation and extracted Windows installer: OK')


if __name__ == '__main__':
    main()
