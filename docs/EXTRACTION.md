# Extraction backends and 7-Zip

llvmup unpacks downloads with the backend that can read the format, through one entry point
(`Invoke-LlvmArchiveExtract` in PowerShell, `eng_extract` in Bash). Choose it with
`--extractor auto|7z|tar|zip|python` or `LLVMUP_EXTRACTOR`.

| Format | `auto` order on Windows | Notes |
| --- | --- | --- |
| `.zip` | built-in .NET ZIP reader | Entries are validated before anything is written |
| `.7z` | 7-Zip (15+) | WinLibs; without 7-Zip the resolver picks the `.zip` of the same release |
| `.tar.zst` | tar with zstd, then 7-Zip with zstd (streamed), then Python 3.14+ | Official LLVM 23+; 1 GiB zstd window |
| `.tar.xz` | 7-Zip (streamed), then tar with xz, then Python | The Windows inbox `tar.exe` has no xz/zstd |
| `.exe` (official NSIS installer) | 7-Zip unpacks the payload; the installer is never executed | Only with `--installer` |

Rules:

- An explicit `--extractor` is validated and never silently replaced. `auto` may fall back when a
  backend is absent or cannot read the format, never to hide a failure: a CRC/data error, a
  non-zero exit code or an unexpected tree stops the installation.
- The resolver only selects assets in formats some local backend can read. When a matching asset
  exists but nothing can unpack it, the error says so (and how to fix it) instead of claiming that
  no release matches.
- Extraction writes to a staging directory next to the destination; entries that escape it,
  links/reparse points and unexpected layouts are rejected; the staged tree is **moved** into place
  (no recursive copy) only after validation.
- 7-Zip is optional and never installed automatically. Discovery looks at `LLVMUP_7Z_PATH`, `PATH`
  (`7z`, `7zz`, `7za`), `C:\Program Files\7-Zip`, `C:\Program Files (x86)\7-Zip` and the registry,
  probes each candidate's version and formats, keeps the newest modern one, and always invokes it by
  its absolute path. An ancient 7-Zip earlier on `PATH` (for example 4.65 without xz) is not used.

## 7-Zip strategies for `.tar.*`

`LLVMUP_7Z_TAR_STRATEGY` selects how the two 7-Zip processes (decompressor `-so`, tar extractor
`-si -ttar`) are connected:

- `pipe` (Windows only, default on Windows): cmd.exe's binary pipe. Fastest in the benchmark and the only connection
  that worked in Windows Sandbox. The decompressor's errors go to a temporary file and fail the
  extraction. Paths containing `%` or `"` cannot be passed safely through cmd.exe; `auto` then uses
  `stream`.
- `stream` (default elsewhere): the processes are wired through .NET process streams by an explicit
  copy loop - never through the PowerShell pipeline, which turns bytes into text on PowerShell 5.1.
  7-Zip's tar side stops reading at the end-of-archive marker and exits 0 while the decompressor
  still writes zero padding: the remainder is drained and must be padding. A failing tar side stops
  the decompressor and its error is reported. If the tar side exits without extracting anything
  (observed in Windows Sandbox: banner, exit 0, nothing read), the Windows extractor retries the
  same archive with `pipe`. This fallback also applies when `stream` was selected explicitly.
- `temp`: decompress to a temporary `.tar`, then extract it (needs the full `.tar` size in temp).

No intermediate `.tar` is written by `pipe` or `stream`.

## Benchmark

`scripts/benchmark_extract.ps1` extracts real archives with every applicable backend through the
same code path and records extractor version, archive SHA-256, sizes, phase times, temporary space,
and a content fingerprint (path + size of every file plus hashes of key binaries) to check that all
backends produce the same tree:

```powershell
powershell -File scripts\benchmark_extract.ps1 -Archive 'a.tar.zst,b.zip' -WorkDir D:\bench -OutFile bench.json
```

Results on Windows 10 22H2 (build 19045, 12 logical CPUs, Windows PowerShell 5.1), 7-Zip 26.06, Windows inbox bsdtar 3.5.2
(no xz/zstd), Python 3.14.4. The host was also running a Windows Sandbox VM, so absolute times are
pessimistic; the relative order is what the policy uses. All successful backends of an archive
produced identical trees.

| Archive (compressed -> extracted, files) | Backend | Decompress | Extract | Total | Temp space |
| --- | --- | --- | --- | --- | --- |
| official `clang+llvm-23.1.6-x86_64-pc-windows-msvc.tar.zst` (276 MB -> 4.28 GB, 4,701) | 7-Zip stream | - | - | **24.1 s** | 0 |
| | Python 3.14 tarfile | - | - | 27.1 s | 0 |
| | 7-Zip temp `.tar` | 12.9 s | 26.7 s | 39.6 s | 4.28 GB |
| | 7-Zip `pipe` (cmd.exe), idle host | - | - | **19 s** | 0 |
| | 7-Zip `stream` (explicit .NET copy loop), idle host | - | - | 40 s | 0 |
| | inbox tar | not possible (no zstd) | | | |
| winlibs `...-r3.7z` (189 MB -> 1.71 GB, 12,931) | 7-Zip | - | - | 33.9 s | 0 |
| llvm-mingw `20261117-ucrt-x86_64.zip` (191 MB -> 753 MB, 9,069) | Python zipfile | - | - | 31.0 s | 0 |
| | built-in .NET ZIP | - | - | 36.3 s | 0 |
| | 7-Zip | - | - | 47.9 s | 0 |
| llvm-mingw `ubuntu-22.04-x86_64.tar.xz` (84 MB) on Windows | 7-Zip | refused: archive contains symbolic links ("Dangerous link path was ignored") | | | |

Second run on an idle host (PowerShell 7.7, 7-Zip 26.06, `-Repeat 1`, archives from the llvmup
cache; every backend of an archive produced an identical tree, `equivalent = true`):

| Archive | Backend | Total |
| --- | --- | --- |
| llvm-mingw `20261117-ucrt-x86_64.zip` (9,069 files) | built-in .NET ZIP | **12.1 s** |
| | Python zipfile | 13.9 s |
| | 7-Zip | 17.1 s |
| winlibs `...-r3.7z` (12,931 files) | 7-Zip | 27.6 s |
| winlibs `...-r3.zip` | built-in .NET ZIP | **27.6 s** |
| | Python zipfile | 34.1 s |
| | 7-Zip | 38.9 s |

On an idle host the built-in reader is the fastest for ZIP, which matches the `auto` policy.

Conclusions used by `auto`:

- `.tar.zst`/`.tar.xz` with 7-Zip: connecting the processes directly is faster than the temp-file
  strategy and needs no temporary space. The cmd.exe pipe beats the .NET copy loop by about 2x, so it
  is the Windows default. (The first `stream` row used `Stream.CopyTo`, which could deadlock and was
  replaced by the explicit loop.)
- `.tar.zst` is preferred over the 3.3x larger `.tar.xz` of the same official release whenever a
  zstd-capable backend exists (smaller download, faster extraction).
- `.zip`: the built-in reader needs no external program and is faster than 7-Zip; Python is
  slightly faster but optional, so it is used only when selected explicitly.
- Archives made for Linux (symlinks) are not meant to be unpacked on Windows; the resolver picks
  the asset of the current host.
