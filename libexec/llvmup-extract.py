#!/usr/bin/env python3
"""Optional, dependency-free archive extractor backend for llvmup.

Used only when selected (``--extractor python``) or when no native backend can read a
format (for example ``.tar.zst`` on Windows, where the inbox tar.exe has no zstd and
mainline 7-Zip has no zstd codec). Python is never required by llvmup.

Usage:
    llvmup-extract.py probe
    llvmup-extract.py extract <archive> <destination>

Extraction uses ``tarfile``'s ``data`` filter (PEP 706), which rejects absolute paths,
``..`` components, links pointing outside the destination, and device files.
"""

import json
import os
import sys
import tarfile
import zipfile


def _supports(module):
    try:
        __import__(module)
        return True
    except Exception:
        return False


def probe():
    zstd = False
    if sys.version_info >= (3, 14):
        zstd = _supports("compression.zstd")
    info = {
        "version": "%d.%d.%d" % sys.version_info[:3],
        "executable": sys.executable,
        "data_filter": hasattr(tarfile, "data_filter"),
        "xz": _supports("lzma"),
        "gz": _supports("zlib"),
        "bz2": _supports("bz2"),
        "zstd": zstd,
    }
    print(json.dumps(info))
    return 0


def _safe_zip_extract(archive, dest):
    root = os.path.realpath(dest)
    with zipfile.ZipFile(archive) as zf:
        for member in zf.infolist():
            name = member.filename.replace("\\", "/")
            if name.startswith("/") or (len(name) > 1 and name[1] == ":") or ".." in name.split("/"):
                raise ValueError("unsafe zip entry: %r" % member.filename)
            target = os.path.realpath(os.path.join(root, name))
            if target != root and not target.startswith(root + os.sep):
                raise ValueError("zip entry escapes destination: %r" % member.filename)
        zf.extractall(root)


def extract(archive, dest):
    if not hasattr(tarfile, "data_filter"):
        print("python tarfile lacks the 'data' extraction filter (need Python 3.12+ or a patched 3.8+)", file=sys.stderr)
        return 3
    os.makedirs(dest, exist_ok=True)
    lower = archive.lower()
    if lower.endswith(".zip"):
        _safe_zip_extract(archive, dest)
        return 0
    if lower.endswith((".tar.zst", ".tzst")):
        # Upstream LLVM builds use long-distance matching with a 1 GiB window (windowLog 30);
        # the default decoder limit (windowLog 27) rejects such frames, so raise it explicitly.
        from compression import zstd  # Python 3.14+

        options = {zstd.DecompressionParameter.window_log_max: 31}
        with zstd.ZstdFile(archive, mode="rb", options=options) as zf:
            with tarfile.open(fileobj=zf, mode="r|") as tf:
                tf.extractall(dest, filter="data")
        return 0
    with tarfile.open(archive, mode="r:*") as tf:
        tf.extractall(dest, filter="data")
    return 0


def main(argv):
    if len(argv) >= 2 and argv[1] == "probe":
        return probe()
    if len(argv) == 4 and argv[1] == "extract":
        try:
            return extract(argv[2], argv[3])
        except Exception as exc:  # report a single clear line; never fall back silently
            print("extraction failed: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
            return 2
    print(__doc__, file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
