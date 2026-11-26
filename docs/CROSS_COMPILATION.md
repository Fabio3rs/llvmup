# Cross-compilation and CMake

## Targets inside one bundle

LLVM-MinGW ships several Windows targets in one installation (`x86_64`, `i686`, `aarch64`,
`armv7` `-w64-mingw32`), each with a target-prefixed wrapper (`x86_64-w64-mingw32-clang`, ...) that
selects the target and its sysroot. Choosing a target never duplicates the installation:

```bash
llvmup install llvm-mingw@23
llvmup use llvm-mingw@23 --target aarch64-w64-mingw32      # shell function
llvmup run llvm-mingw@23 --target i686-w64-mingw32 -- clang hello.c -o hello.exe
llvmup which clang --toolchain llvm-mingw@23 --target aarch64-w64-mingw32
```

With a target selected, known tools (`clang`, `clang++`, `ar`, `ranlib`, `windres`, `ld`, ...) resolve
to that target's wrapper, and `CC`, `CXX`, `AR`, `RANLIB`, `RC`/`WINDRES`, `LD`, `NM`, `STRIP` and
`DLLTOOL` point at the wrappers. Tools a distribution does not ship are reported as missing; llvmup
does not fall back to another installation.

## Linux -> Windows

LLVM-MinGW publishes Linux hosts (`ubuntu-*-x86_64` and `aarch64`), so a Linux machine or CI runner
can build Windows programs:

```bash
llvmup install llvm-mingw@23                 # resolves the Linux-hosted asset
llvmup cmake-toolchain llvm-mingw@23 --target x86_64-w64-mingw32 --output build/windows-toolchain.cmake
cmake -S . -B build/win64 -G Ninja -DCMAKE_TOOLCHAIN_FILE=build/windows-toolchain.cmake
cmake --build build/win64
```

Verified on Ubuntu 24.04 (WSL) with llvm-mingw 20261117 (LLVM 23.1.6), installed through the
GitHub Action's provider path from the real GitHub release:

| Target | Compile | Link | Binary inspection | Execution |
| --- | --- | --- | --- | --- |
| `x86_64-w64-mingw32` | PASS | PASS | PASS (PE32+ x86-64, UCRT imports) | PASS (on the Windows host) |
| `aarch64-w64-mingw32` | PASS | PASS | PASS (PE32+ AArch64) | SKIP (no ARM64 Windows host) |
| CMake + Ninja, x86_64 | PASS | PASS | PASS | not run |

The sample covers C17, C++23 (`std::print`, `std::expected`, ranges), `std::vector`,
`std::filesystem`, `std::thread`, exceptions, a static library, a DLL with an import library and a
Windows resource. Programs need the toolchain's `libc++.dll` and `libunwind.dll` (in
`<root>/<target>/bin`) next to them, or link with `-static`.

## Generated CMake toolchain files

`llvmup cmake-toolchain [selector] [--target T] [--compiler C] [--output FILE]` writes:

- `CMAKE_SYSTEM_NAME` and `CMAKE_SYSTEM_PROCESSOR` only when actually cross-compiling (setting them
  for a native build would make CMake treat it as a cross build);
- the real `CMAKE_C_COMPILER`/`CMAKE_CXX_COMPILER` paths (target wrappers for llvm-mingw, `gcc`/`g++`
  for WinLibs with `--compiler gcc`);
- `CMAKE_AR`, `CMAKE_RANLIB`, `CMAKE_RC_COMPILER`;
- for cross builds, `CMAKE_FIND_ROOT_PATH` with programs searched on the host
  (`CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER`) and libraries, headers and packages only in the target
  tree (`ONLY`).

PowerShell uses the same command; quote paths that contain spaces:

```powershell
llvmup cmake-toolchain llvm-mingw@23 --target x86_64-w64-mingw32 --output 'build\windows-toolchain.cmake'
cmake -S . -B build\win64 -G Ninja "-DCMAKE_TOOLCHAIN_FILE=$PWD\build\windows-toolchain.cmake"
```

## ABI rules

- Use one build directory per toolchain identity (provider, release, target, compiler, CRT, C++
  library). CMake caches the compiler on first configure; llvmup never rewrites an existing cache.
- Do not mix MSVC STL (official LLVM for `*-windows-msvc`), libstdc++ (WinLibs GCC and Clang) and
  libc++ (llvm-mingw) objects or libraries in one program.
- Do not mix UCRT and MSVCRT builds; llvmup records the CRT in the manifest and in lockfile entries.
- The official Windows LLVM targets MSVC: it needs Visual Studio's headers/libraries and the Windows
  SDK. A clean machine can run it (`clang --version`, freestanding code) but cannot build hosted
  programs without them. WinLibs and llvm-mingw are self-contained and need neither.
