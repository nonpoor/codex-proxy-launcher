#!/usr/bin/env python3
"""Build user ZIPs from an explicit file list; never include local logs/config."""
import argparse
import hashlib
from pathlib import Path
import re
import stat
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def build(version: str, output: Path) -> list[Path]:
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Use a version such as 1.0.0, without a v prefix")
    output.mkdir(parents=True, exist_ok=True)
    common = [ROOT / name for name in ("README.md", "README.txt", "LICENSE", "NOTICE.md")]
    common += sorted((ROOT / "docs").glob("*.md"))
    windows = common + [ROOT / "Install-Windows.cmd"] + [ROOT / 'windows' / name for name in (
        'ProxyRoute.ps1', 'Start-CodexProxy.ps1', 'Start-CodexProxy.cmd',
        'Diagnose-CodexNetwork.ps1', 'Diagnose-CodexNetwork.cmd', 'Start-CodexCLI.ps1',
        'InstallSupport.ps1', 'Install-CodexProxy.ps1', 'CodexProxy.ico')]
    macos = common + [ROOT / "diagnose-codex-network.command", ROOT / "shell/proxy.zsh"]
    macos += [ROOT / 'lib' / name for name in ('proxy-route.zsh', 'codex-runtime.zsh')]
    macos += [ROOT / 'Codex Proxy.app/Contents' / name for name in (
        'Info.plist', 'MacOS/codex-proxy-launcher', 'Resources/CodexProxy.icns')]
    archives = []
    for platform, files in (("windows", windows), ("macos", macos)):
        folder = f"codex-proxy-launcher-{version}-{platform}"
        archive = output / f"{folder}.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
            for path in files:
                if not path.is_file() or path.is_symlink():
                    raise ValueError(f"Expected ordinary release file: {path}")
                relative = path.relative_to(ROOT)
                if any(p in relative.parts for p in ("logs", ".git", "assets", "__pycache__")):
                    raise ValueError(f"Forbidden release path: {relative}")
                data = path.read_bytes()
                if path.suffix in {'.md', '.txt', '.ps1', '.zsh', '.command', '.plist'} or \
                    path.name in {'LICENSE', 'codex-proxy-launcher'}:
                    data = data.replace(b'\r\n', b'\n')
                if path.suffix == ".cmd":
                    data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
                info = zipfile.ZipInfo(f"{folder}/{relative.as_posix()}", (2026, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.compress_type = zipfile.ZIP_DEFLATED
                # Windows checkouts do not retain POSIX executable bits. Derive
                # launch permissions from the release contract on every host.
                executable = path.suffix in {'.zsh', '.command'} or relative.as_posix() == \
                    'Codex Proxy.app/Contents/MacOS/codex-proxy-launcher'
                mode = 0o755 if executable else 0o644
                info.external_attr = (stat.S_IFREG | mode) << 16
                zf.writestr(info, data)
            version_info = zipfile.ZipInfo(f"{folder}/VERSION", (2026, 1, 1, 0, 0, 0))
            version_info.create_system = 3
            version_info.compress_type = zipfile.ZIP_DEFLATED
            version_info.external_attr = (stat.S_IFREG | 0o644) << 16
            zf.writestr(version_info, version + "\n")
        with zipfile.ZipFile(archive) as zf:
            if zf.testzip() is not None:
                raise ValueError(f"Corrupt archive: {archive}")
        archives.append(archive)
    sums = "".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in archives)
    (output / "SHA256SUMS.txt").write_text(sums, encoding="ascii")
    return archives


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="Release version, for example 1.0.0")
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    for result in build(args.version, args.output):
        print(result)
