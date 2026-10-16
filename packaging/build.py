#!/usr/bin/env python3
"""Build explicit, reproducible runtime packages; Python is a maintainer dependency only."""
import argparse
import gzip
import hashlib
import io
from pathlib import Path
import re
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def build(version, output):
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?", version):
        raise ValueError("Expected a release tag such as v0.6.0 or v0.6.0-rc.1")
    manifest = ROOT / "packaging/runtime-files.tsv"
    rows = []
    names = set()
    for line in manifest.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        platform, mode, name = line.split()
        if platform not in ("common", "bash", "powershell") or mode not in ("644", "755"):
            raise ValueError(f"Invalid manifest entry: {line}")
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", name) or name in names:
            raise ValueError(f"Unsafe or duplicate filename: {name}")
        names.add(name)
        if (ROOT / name).is_symlink():
            raise ValueError(f"Symlinks cannot be packaged: {name}")
        rows.append((platform, int(mode, 8), name, (ROOT / name).read_bytes()))
    output.mkdir(parents=True, exist_ok=True)
    assets = []
    for platform, filename in (("bash", "llvmup-linux.tar.gz"), ("powershell", "llvmup-windows.zip")):
        files = {name: (mode, data) for p, mode, name, data in rows if p in ("common", platform)}
        extras = ["packaging/runtime-files.tsv"]
        extras += ["install.sh", "packaging/install-files.sh"] if platform == "bash" else ["packaging/Install-Llvmup.ps1"]
        for name in extras:
            files[name] = (0o644, (ROOT / name).read_bytes())
        files["VERSION"] = (0o644, (version + "\n").encode())
        path = output / filename
        if platform == "bash":
            with path.open("wb") as raw, gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as gz, tarfile.open(fileobj=gz, mode="w") as archive:
                for name, (mode, data) in sorted(files.items()):
                    info = tarfile.TarInfo("llvmup/" + name)
                    info.mode, info.size, info.mtime = mode, len(data), 0
                    archive.addfile(info, io.BytesIO(data))
        else:
            with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                for name, (mode, data) in sorted(files.items()):
                    info = zipfile.ZipInfo("llvmup/" + name, (1980, 1, 1, 0, 0, 0))
                    info.external_attr = (0o100000 | mode) << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    archive.writestr(info, data)
        assets.append(path)
    for name in ("bootstrap.sh", "bootstrap.ps1"):
        path = output / name
        # Pin even the latest-release bootstrap to its own release to avoid
        # mixing archives/checksums if a new release appears during download.
        path.write_bytes((ROOT / "packaging" / name).read_bytes().replace(b"@LLVMUP_VERSION@", version.encode()))
        assets.append(path)
    (output / "SHA256SUMS").write_text("".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n" for p in assets))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    build(args.version, args.output)
