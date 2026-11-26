# Providers and variants

`llvmup install <provider>@<version>` installs from one of the providers below. The version after
`@` is always the **LLVM** version, also for WinLibs where GCC can be the active compiler. Without a
provider, remote operations use `official`.

```text
llvmup install official@23                 # newest 23.x.y
llvmup install winlibs@23.1 --name win-dev # newest WinLibs bundle with LLVM 23.1.x
llvmup install llvm-mingw@23               # newest dated release shipping LLVM 23.x
llvmup install --provider llvm-mingw --release 20261117
llvmup resolve 'winlibs@~23.1' --format json
llvmup list --remote --provider winlibs
```

Selectors: `latest`, `X`, `X.Y`, `X.Y.Z`, `~X.Y`, `X.*`, `>=X.Y.Z`, ... (one expression; compound
ranges are rejected). `--release` selects an exact upstream tag. Drafts and prereleases are skipped.
Releases are paginated, so old versions can be found. Host, architecture, CRT, threads and target
are applied **before** picking the newest release, so an incompatible newer release is never
chosen. WinLibs revisions compare numerically (`r10` > `r9`).

## official — `llvm/llvm-project`

| | |
| --- | --- |
| Identity | `llvmorg-X.Y.Z` (canonical id = tag; legacy name kept) |
| Hosts | Windows x64/arm64/x86, Linux x64/arm64, macOS arm64/x64 (as published per release) |
| Formats | `.tar.zst` preferred when a zstd backend exists, `.tar.xz`, NSIS `.exe` (`--installer`) |
| Profiles | `minimal`, `compiler`, `full`, `custom` (selective extraction), source builds |
| Verification | GPG `.sig`, Sigstore/GitHub attestations `.jsonl`, checksums when published |
| Windows target | `*-windows-msvc`: needs Visual Studio headers/libraries and the Windows SDK |

## winlibs — `brechtsanders/winlibs_mingw`

| | |
| --- | --- |
| Identity | `winlibs-<gcc>posix-<llvm>-<mingw>-<crt>-r<N>-<arch>` |
| Hosts | Windows |
| Variants | arch `x64` (x86_64, SEH) and `x86` (i686, DWARF); CRT `ucrt` (default) or `msvcrt`; threads `posix` (default) |
| Formats | `.7z` with a modern 7-Zip, otherwise the `.zip` of the same release |
| Bundle | GCC, LLVM/Clang/LLD/LLDB, MinGW-w64, GDB, CMake, Ninja, binutils in one tree |
| Compilers | `clang` (default) and `gcc` from the same installation: `--compiler gcc` |
| Verification | `.sha256`/`.sha512` (integrity only; no upstream signatures) |
| Profiles | `full` |

Releases without LLVM (GCC-only assets) are never selected. GCC uses `gcc-ar`/`gcc-ranlib`/`gcc-nm`
(as WinLibs' own `mingwvars.bat`). **GCC cannot link from an installation path containing spaces**
(see `docs/INSTALL.md`); llvmup warns about it.

## llvm-mingw — `mstorsjo/llvm-mingw`

| | |
| --- | --- |
| Identity | `llvm-mingw-<YYYYMMDD>-<crt>-<host os>-<host arch>` |
| Release vs LLVM | Dated tags; the LLVM version is read from the release metadata (`LLVM 23.1.6`), never by running code |
| Hosts | Windows x64/arm64/x86 (`.zip`), Linux x64/arm64 (`ubuntu-*.tar.xz`), macOS universal (`.tar.xz`) |
| CRT | `ucrt` (default) or `msvcrt` |
| Targets | `x86_64`, `i686`, `aarch64`, `armv7` `-w64-mingw32` in one installation: `--target` |
| Tools | Target-prefixed wrappers (`<target>-clang`, `-clang++`, `-windres`, `-ar`, ...), `ld.lld`; no `lld-link`, no `llvm-config`/libclang development files |
| Runtimes | `<target>/bin` (libc++, libunwind, libwinpthread) is put before `bin/` for the selected target |
| Verification | checksums when published (integrity only) |
| Profiles | `full` |

Capabilities are discovered from the files actually present and recorded in
`.llvmup-toolchain.json`; llvmup does not assume the official tool set.

## Verified on real toolchains

`scripts/toolchain_matrix.ps1` installs each toolchain with llvmup from the GitHub releases and builds
a fixed sample with `llvmup run`, with `PATH` reduced to `System32` (plus cmake/ninja for the CMake
step). Reproduce with
`pwsh -File scripts\toolchain_matrix.ps1 -LlvmHome C:\llvmup-matrix -Configs lm-x64,lm-i686,lm-arm64,wl-clang,wl-gcc -OutFile matrix.json`.

Sample: C17, C++23 (`std::vector`, ranges, `std::expected`, `std::filesystem`, `std::thread`,
exceptions), a static library, a DLL with import library, a Windows resource (`.rc`), debug info, a
check that every system include directory is inside the toolchain, a PE inspection (machine,
sections, imported DLLs) and CMake + Ninja through `llvmup cmake-toolchain`.

Windows 10 22H2 x64 host (PowerShell 7 and 5.1) and a clean Windows Sandbox (Windows PowerShell 5.1
only, no compilers, SDKs or 7-Zip; package built by `packaging/build.py` and installed outside the
checkout by the bootstrap; home `C:\llvmup-matrix`, no spaces):

| Configuration | Compile | Link | PE inspection | Execute | Static lib | DLL | `.rc` | Debug info | Headers | CMake + Ninja |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| llvm-mingw 20261117 x86_64 (host, Sandbox) | PASS | PASS | PASS (x64) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| llvm-mingw 20261117 i686 (host, Sandbox) | PASS | PASS | PASS (x86) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| llvm-mingw 20261117 aarch64 (host, Sandbox) | PASS | PASS | PASS (ARM64) | SKIP (no ARM64 host) | PASS | PASS | PASS | PASS | PASS | PASS |
| WinLibs 16.2.0 / LLVM 23.1.3 UCRT, Clang (host, Sandbox) | PASS | PASS | PASS (x64) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| WinLibs 16.2.0 / LLVM 23.1.3 UCRT, GCC (host, Sandbox) | PASS | PASS | PASS (x64) | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| WinLibs GCC with a space in the toolchains path (host) | PASS | **FAIL** | - | - | FAIL | FAIL | FAIL | - | PASS | - |
| llvm-mingw 20261117 on Linux (WSL1) -> x86_64 / aarch64 | PASS | PASS | PASS | x86_64 PASS on the Windows host | - | - | - | - | - | PASS |

Notes:

- The failing row is the documented upstream limitation: WinLibs GCC (`collect2`/`ld`) cannot link
  when the installation path contains spaces; WinLibs Clang from the same bundle is unaffected.
- C++ programs built with llvm-mingw need `libc++.dll` and `libunwind.dll` from the toolchain's
  `<target>/bin`. Run without llvmup's environment they fail to load, which shows the runtime DLLs
  come from the selected toolchain only. Copy them next to the program to run it elsewhere.
- Official LLVM on Windows targets MSVC and needs Visual Studio/Windows SDK for hosted builds; the
  matrix only checks that it starts (`official` configuration).
- Official LLVM 23.1.6 for Linux x64 (`.tar.zst`, 1.2 GB) was downloaded, verified (sha256) and
  extracted by the Bash engine. On WSL1 the kernel loader cannot execute the 282 MB `clang-23`
  directly (`Exec format error`), so llvmup's validation step rejected the install there. Started
  through the dynamic loader (`ld-linux-x86-64.so.2 clang-23`) the same file runs: `clang 23.1.6`
  compiled a C17 and a C++23 (`libstdc++`) program, linked with the system `g++` and executed
  (`official-linux sum=6`). A direct, unassisted install-and-build on a real Linux host or WSL2 is
  still pending.
- Windows PowerShell 5.1 (`-File`) rejects a lone `-` argument (for example `clang -x c -`) before
  llvmup runs; use PowerShell 7 or pass a file instead.

Not verified: WinLibs MCF threads, WinLibs i686/MSVCRT end to end, llvm-mingw MSVCRT and armv7
execution, macOS hosts, Windows ARM64 hosts.
