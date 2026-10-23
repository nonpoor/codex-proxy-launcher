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
    windows = common + [ROOT / "Install-Windows.cmd"] + sorted((ROOT / "windows").glob("*.ps1"))
    windows += sorted((ROOT / "windows").glob("*.cmd"))
    macos = common + [ROOT / "diagnose-codex-network.command", ROOT / "shell/proxy.zsh"]
    macos += sorted((ROOT / "lib").glob("*.zsh"))
    macos += sorted(p for p in (ROOT / "Codex Proxy.app").rglob("*") if p.is_file())
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
                if path.suffix == ".cmd":
                    data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
                info = zipfile.ZipInfo(f"{folder}/{relative.as_posix()}", (2026, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.compress_type = zipfile.ZIP_DEFLATED
                mode = 0o755 if path.stat().st_mode & stat.S_IXUSR else 0o644
                info.external_attr = (stat.S_IFREG | mode) << 16
                zf.writestr(info, data)
            zf.writestr(f"{folder}/VERSION", version + "\n")
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
