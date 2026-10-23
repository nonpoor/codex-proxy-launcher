#!/usr/bin/env python3
"""Verify the downloadable ZIPs and install from an extracted Windows package."""
import argparse
import hashlib
from pathlib import Path
import shutil
import stat
import struct
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
        checkout = temp / 'windows-style-checkout'
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
                for entry in zf.infolist():
                    relative = Path(entry.filename).relative_to(folder)
                    if relative.name == 'VERSION':
                        continue
                    destination = checkout / relative
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    data = zf.read(entry)
                    if destination.suffix not in {'.icns', '.ico'}:
                        data = data.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
                    destination.write_bytes(data)
                    destination.chmod(0o644)
                if platform == 'windows':
                    assert {'Install-Windows.cmd', 'windows/Install-CodexProxy.ps1',
                            'windows/InstallSupport.ps1', 'windows/ProxyRoute.ps1',
                            'windows/Start-CodexProxy.cmd', 'windows/CodexProxy.ico'} <= names
                    icon = zf.read(folder + '/windows/CodexProxy.ico')
                    reserved, kind, count = struct.unpack_from('<HHH', icon)
                    assert (reserved, kind, count) == (0, 1, 5)
                    sizes = set()
                    for i in range(count):
                        width, height, _, _, planes, depth, length, offset = struct.unpack_from('<BBBBHHII', icon, 6 + 16*i)
                        width, height = width or 256, height or 256
                        assert planes == 1 and depth == 32 and offset + length <= len(icon)
                        frame = icon[offset:offset+length]
                        assert frame.startswith(b'\x89PNG\r\n\x1a\n')
                        assert struct.unpack('>II', frame[16:24]) == (width, height)
                        sizes.add(width)
                    assert sizes == {16, 32, 64, 128, 256}
                    for name in zf.namelist():
                        if name.endswith('.cmd'):
                            assert b'\n' not in zf.read(name).replace(b'\r\n', b'')
                    zf.extractall(temp / 'extracted')
                else:
                    entry = zf.getinfo(folder + '/Codex Proxy.app/Contents/MacOS/codex-proxy-launcher')
                    assert (entry.external_attr >> 16) & stat.S_IXUSR
                    assert b'\r\n' not in zf.read(entry)
                    assert {'lib/proxy-route.zsh', 'lib/codex-runtime.zsh',
                            'diagnose-codex-network.command'} <= names
            expected = hashlib.sha256(archive.read_bytes()).hexdigest()
            assert f'{expected}  {archive.name}' in (output / 'SHA256SUMS.txt').read_text()
        # Simulate Windows CRLF checkout and missing POSIX execute bits on every
        # platform, including machines where native checkout has LF/755 files.
        (checkout / 'scripts').mkdir()
        shutil.copyfile(ROOT / 'scripts/build-release.py', checkout / 'scripts/build-release.py')
        simulated = temp / 'simulated-packages'
        subprocess.run([sys.executable, str(checkout / 'scripts/build-release.py'), '1.0.0',
                        '--output', str(simulated)], check=True, capture_output=True)
        for archive in output.glob('*.zip'):
            with zipfile.ZipFile(archive) as expected, zipfile.ZipFile(simulated / archive.name) as actual:
                for entry in expected.infolist():
                    other = actual.getinfo(entry.filename)
                    assert expected.read(entry) == actual.read(other), f'Content differs: {entry.filename}'
                    assert entry.date_time == other.date_time, f'Timestamp differs: {entry.filename}'
                    assert entry.external_attr == other.external_attr, f'Mode differs: {entry.filename}'
            assert archive.read_bytes() == (simulated / archive.name).read_bytes()
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
        assert (installed / 'windows/CodexProxy.ico').is_file()
        assert (installed / '.codex-proxy-launcher.install').is_file()
        assert not (installed / 'logs').exists()
    print('Release ZIP validation and extracted Windows installer: OK')


if __name__ == '__main__':
    main()
