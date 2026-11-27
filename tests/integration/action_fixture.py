"""Build an offline official release fixture consumed by the composite action."""
import hashlib
import io
import json
import os
import platform
from pathlib import Path
import tarfile

root = Path(os.environ["RUNNER_TEMP"]).resolve()
system = platform.system()
arch = platform.machine().lower()
windows = system == "Windows"
arm64 = arch in {"aarch64", "arm64"}
suffix = {
    "Windows": f"{'aarch64' if arm64 else 'x86_64'}-pc-windows-msvc",
    "Linux": f"Linux-{'ARM64' if arm64 else 'X64'}",
    "Darwin": f"macOS-{'ARM64' if arm64 else 'X64'}",
}[system]
prefix = "clang+llvm" if windows else "LLVM"
archive = root / f"{prefix}-20.1.8-{suffix}.tar.xz"
with tarfile.open(archive, "w:xz") as package:
    for tool in ("clang", "clang++", "lld-link" if windows else "lld"):
        name = f"{tool}.cmd" if windows else tool
        body = b"@echo off\r\necho clang version 20.1.8\r\n" if windows else b"#!/bin/sh\necho clang version 20.1.8\n"
        member = tarfile.TarInfo(f"fixture/bin/{name}")
        member.mode = 0o755
        member.size = len(body)
        package.addfile(member, io.BytesIO(body))

asset = {
    "id": 1,
    "name": archive.name,
    "size": archive.stat().st_size,
    "browser_download_url": archive.as_uri(),
    "digest": "sha256:" + hashlib.sha256(archive.read_bytes()).hexdigest(),
}
release = {"tag_name": "llvmorg-20.1.8", "draft": False, "prerelease": False, "assets": [asset]}
(root / "llvmup-action-releases.json").write_text(json.dumps([release]), encoding="utf-8")
