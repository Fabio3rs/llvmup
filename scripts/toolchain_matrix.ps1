<#
.SYNOPSIS
Reproducible real-toolchain matrix: installs toolchains with llvmup and builds/links/inspects/runs a
fixed sample with each of them.

.DESCRIPTION
Every build step runs through `llvmup run` (the exported environment is the only thing that provides
compilers, headers, libraries and runtime DLLs) with a PATH reduced to System32 (plus cmake/ninja
directories for the CMake step). Arguments are passed as an argument list; nothing goes through
cmd.exe quoting, and each step's working directory is the configuration's own directory.

Per configuration it records PASS/FAIL/SKIP for: Compile, Link, Inspect, Execute (C17 and C++23
sample: std::vector, std::filesystem, std::thread, exceptions, ranges, std::expected), Static library,
DLL + import library, Windows resource (.rc), Debug info (DWARF/CodeView sections), header origin
(every system include directory must be inside the toolchain) and CMake + Ninja.

The official Windows LLVM targets MSVC and needs Visual Studio/Windows SDK headers and libraries:
its configuration only checks that the compiler starts and compiles freestanding code, and records
Link/Execute as SKIP.

.EXAMPLE
pwsh -File scripts/toolchain_matrix.ps1 -LlvmHome C:\llvmup-matrix -Configs lm-x64,lm-i686,wl-clang,wl-gcc
#>
[CmdletBinding()]
param(
    [string]$LlvmHome = 'C:\llvmup-matrix',
    [string[]]$Configs = @('lm-x64', 'lm-i686', 'lm-arm64', 'wl-clang', 'wl-gcc'),
    [string]$Work = '',
    [string]$OutFile = '',
    [string]$LlvmMingw = 'llvm-mingw@latest',
    [string]$WinLibs = 'winlibs@latest',
    [string]$Official = 'official@latest',
    [string]$LlvmupRoot = '',
    [switch]$NoInstall
)
$ErrorActionPreference = 'Stop'
$Configs = @($Configs | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$repo = if ($LlvmupRoot) { $LlvmupRoot } else { Split-Path $PSScriptRoot -Parent }
$cli = Join-Path $repo 'libexec\pwsh\llvmup-cli.ps1'
$psExe = (Get-Process -Id $PID).Path
if (-not $Work) { $Work = Join-Path $LlvmHome 'matrix-work' }
$env:LLVM_HOME = $LlvmHome
if ($LlvmHome -match '\s') { Write-Warning "Home '$LlvmHome' contains whitespace: WinLibs GCC is expected to fail to link." }

$sys32 = Join-Path $env:SystemRoot 'System32'
$cleanPath = "$sys32;$env:SystemRoot"
$extraDirs = @()
foreach ($t in 'cmake.exe', 'ninja.exe') {
    $c = Get-Command $t -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { $extraDirs += (Split-Path $c.Source -Parent) }
}
$cmakePath = ((@($extraDirs | Select-Object -Unique) + $cleanPath) -join ';')
$hasCMake = (@($extraDirs).Count -ge 1) -and (Get-Command cmake.exe -ErrorAction SilentlyContinue) -and (Get-Command ninja.exe -ErrorAction SilentlyContinue)
$hostPath = $env:PATH

# ---------------------------------------------------------------- helpers
function Invoke-Llvmup {
    param([string[]]$Arguments, [string]$Path = $cleanPath, [string]$Cwd = $PWD.Path)
    $old = $env:PATH; $oldEap = $ErrorActionPreference
    $env:PATH = $Path; $ErrorActionPreference = 'Continue'
    Push-Location -LiteralPath $Cwd
    try {
        $out = & $psExe -NoProfile -ExecutionPolicy Bypass -File $cli --llvmup-args @Arguments 2>&1 | ForEach-Object { "$_" }
        $rc = $LASTEXITCODE
    } finally { Pop-Location; $env:PATH = $old; $ErrorActionPreference = $oldEap }
    [pscustomobject]@{ ExitCode = $rc; Output = (@($out) -join "`n") }
}

function Get-PeInfo([string]$File) {
    $b = [IO.File]::ReadAllBytes($File)
    $pe = [BitConverter]::ToInt32($b, 0x3c)
    if ([Text.Encoding]::ASCII.GetString($b, $pe, 4) -ne "PE`0`0") { throw "$File is not a PE file" }
    $machine = [BitConverter]::ToUInt16($b, $pe + 4)
    $nsec = [BitConverter]::ToUInt16($b, $pe + 6)
    $optSize = [BitConverter]::ToUInt16($b, $pe + 20)
    $opt = $pe + 24
    $magic = [BitConverter]::ToUInt16($b, $opt)
    $ddOff = if ($magic -eq 0x20b) { $opt + 112 } else { $opt + 96 }
    $importRva = [BitConverter]::ToUInt32($b, $ddOff + 8)
    $resRva = [BitConverter]::ToUInt32($b, $ddOff + 16)
    $secs = @(); $secBase = $opt + $optSize
    for ($i = 0; $i -lt $nsec; $i++) {
        $o = $secBase + 40 * $i
        $secs += [pscustomobject]@{
            Name = ([Text.Encoding]::ASCII.GetString($b, $o, 8)).TrimEnd("`0")
            VSize = [BitConverter]::ToUInt32($b, $o + 8); Rva = [BitConverter]::ToUInt32($b, $o + 12)
            RawPtr = [BitConverter]::ToUInt32($b, $o + 20)
        }
    }
    function Rva2Off($rva) {
        foreach ($s in $secs) { if ($rva -ge $s.Rva -and $rva -lt ($s.Rva + [Math]::Max($s.VSize, 1))) { return [int]($rva - $s.Rva + $s.RawPtr) } }
        return -1
    }
    $imports = @()
    if ($importRva) {
        $o = Rva2Off $importRva
        while ($o -ge 0) {
            $nameRva = [BitConverter]::ToUInt32($b, $o + 12)
            if ($nameRva -eq 0) { break }
            $no = Rva2Off $nameRva; $e = $no
            while ($b[$e] -ne 0) { $e++ }
            $imports += [Text.Encoding]::ASCII.GetString($b, $no, $e - $no)
            $o += 20
        }
    }
    $arch = switch ($machine) { 0x8664 { 'x64' } 0x14c { 'x86' } 0xAA64 { 'arm64' } 0x1c4 { 'arm' } default { ('0x{0:x}' -f $machine) } }
    [pscustomobject]@{ Arch = $arch; Sections = @($secs.Name); Imports = $imports; HasResources = ($resRva -ne 0) }
}

# ---------------------------------------------------------------- sample sources
$sources = @{
    'c17.c'    = "#include <stdio.h>`n#include <stdbool.h>`nint main(void){ bool ok = true; _Static_assert(__STDC_VERSION__ >= 201710L, `"C17`"); puts(ok ? `"C17 OK`" : `"bad`"); return 0; }`n"
    'cxx23.cpp' = @'
#include <vector>
#include <numeric>
#include <filesystem>
#include <thread>
#include <iostream>
#include <stdexcept>
#include <expected>
#include <ranges>
static std::expected<int, int> half(int x) { if (x % 2) return std::unexpected(x); return x / 2; }
int main() {
  std::vector<int> v{1, 2, 3, 4};
  int s = std::accumulate(v.begin(), v.end(), 0);
  for (int x : v | std::views::filter([](int i) { return i % 2 == 0; })) s += x;
  std::thread t([&] { s += 100; }); t.join();
  try { throw std::runtime_error("boom"); } catch (const std::exception&) { s += 1000; }
  auto h = half(8);
  bool fs = !std::filesystem::current_path().empty();
  std::cout << "CXX23 OK sum=" << s << " half=" << h.value_or(-1) << " fs=" << fs << "\n";
  return (s == 1116 && h && *h == 4 && fs) ? 0 : 1;
}
'@
    'empty.cpp' = ""
    'lib.c'    = "int answer(void){ return 42; }`n"
    'uselib.c' = "#include <stdio.h>`nint answer(void);`nint main(void){ printf(`"STATIC %d\n`", answer()); return answer()==42?0:1; }`n"
    'dll.c'    = "__declspec(dllexport) int dll_answer(void){ return 7; }`n"
    'usedll.c' = "#include <stdio.h>`n__declspec(dllimport) int dll_answer(void);`nint main(void){ printf(`"DLL %d\n`", dll_answer()); return dll_answer()==7?0:1; }`n"
    'userc.c'  = "#include <stdio.h>`nint main(void){ puts(`"RC linked`"); return 0; }`n"
    'res.rc'   = "1 VERSIONINFO`nFILEVERSION 1,2,3,4`nBEGIN`n BLOCK `"StringFileInfo`"`n BEGIN`n  BLOCK `"040904B0`"`n  BEGIN`n   VALUE `"FileDescription`", `"llvmup matrix`"`n  END`n END`nEND`n"
    'CMakeLists.txt' = "cmake_minimum_required(VERSION 3.20)`nproject(matrix LANGUAGES C CXX)`nset(CMAKE_CXX_STANDARD 23)`nset(CMAKE_CXX_STANDARD_REQUIRED ON)`nadd_executable(cm cxx23.cpp)`n"
}

# ---------------------------------------------------------------- configurations
# sel: selector for llvmup; run: extra llvmup run options; tool names are what `llvmup run` resolves.
$cfgTable = @{
    'lm-x64'   = @{ install = @($LlvmMingw, '--crt', 'ucrt'); sel = $LlvmMingw; run = @('--target', 'x86_64-w64-mingw32'); cc = 'x86_64-w64-mingw32-clang'; cxx = 'x86_64-w64-mingw32-clang++'; ar = 'llvm-ar'; rc = 'x86_64-w64-mingw32-windres'; arch = 'x64'; exec = $true; kind = 'mingw'; cmakeArgs = @('--target', 'x86_64-w64-mingw32') }
    'lm-i686'  = @{ install = @($LlvmMingw, '--crt', 'ucrt'); sel = $LlvmMingw; run = @('--target', 'i686-w64-mingw32'); cc = 'i686-w64-mingw32-clang'; cxx = 'i686-w64-mingw32-clang++'; ar = 'llvm-ar'; rc = 'i686-w64-mingw32-windres'; arch = 'x86'; exec = $true; kind = 'mingw'; cmakeArgs = @('--target', 'i686-w64-mingw32') }
    'lm-arm64' = @{ install = @($LlvmMingw, '--crt', 'ucrt'); sel = $LlvmMingw; run = @('--target', 'aarch64-w64-mingw32'); cc = 'aarch64-w64-mingw32-clang'; cxx = 'aarch64-w64-mingw32-clang++'; ar = 'llvm-ar'; rc = 'aarch64-w64-mingw32-windres'; arch = 'arm64'; exec = $false; kind = 'mingw'; cmakeArgs = @('--target', 'aarch64-w64-mingw32') }
    'wl-clang' = @{ install = @($WinLibs, '--crt', 'ucrt'); sel = $WinLibs; run = @('--compiler', 'clang'); cc = 'clang'; cxx = 'clang++'; ar = 'llvm-ar'; rc = 'windres'; arch = 'x64'; exec = $true; kind = 'mingw'; cmakeArgs = @('--compiler', 'clang') }
    'wl-gcc'   = @{ install = @($WinLibs, '--crt', 'ucrt'); sel = $WinLibs; run = @('--compiler', 'gcc'); cc = 'gcc'; cxx = 'g++'; ar = 'ar'; rc = 'windres'; arch = 'x64'; exec = $true; kind = 'mingw'; cmakeArgs = @('--compiler', 'gcc') }
    'official' = @{ install = @($Official); sel = $Official; run = @(); cc = 'clang'; cxx = 'clang++'; ar = 'llvm-ar'; rc = ''; arch = 'x64'; exec = $false; kind = 'msvc'; cmakeArgs = @() }
}

$results = New-Object System.Collections.Generic.List[object]
$steps = 'Compile', 'Link', 'Inspect', 'Execute', 'Static', 'Dll', 'Resource', 'Debug', 'Headers', 'CMake'

function Add-Step($r, [string]$name, [string]$status, [string]$detail = '') {
    $r.steps[$name] = $status
    if ($detail) { $r.notes += "[$name] $detail" }
    $color = switch ($status) { 'PASS' { 'Green' } 'FAIL' { 'Red' } default { 'Yellow' } }
    Write-Host ("  {0,-10} {1}" -f $name, $status) -ForegroundColor $color
}

function Invoke-Tool {
    # Runs one tool through llvmup with the configuration's options; returns the result object.
    param($c, [string]$Dir, [string[]]$ToolArgs, [string]$Path = $cleanPath)
    Invoke-Llvmup -Arguments (@('run', $c.sel) + $c.run + @('--') + $ToolArgs) -Path $Path -Cwd $Dir
}

foreach ($id in $Configs) {
    if (-not $cfgTable.ContainsKey($id)) { throw "Unknown configuration '$id' (known: $($cfgTable.Keys -join ', '))" }
    $c = $cfgTable[$id]
    $r = [pscustomobject]@{ id = $id; selector = $c.sel; steps = [ordered]@{}; notes = @(); toolchain = ''; seconds = 0 }
    foreach ($s in $steps) { $r.steps[$s] = 'SKIP' }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "== $id ($($c.sel) $($c.run -join ' '))" -ForegroundColor Cyan

    if (-not $NoInstall) {
        $inst = Invoke-Llvmup -Arguments (@('install') + $c.install + @('--quiet')) -Path $hostPath
        if ($inst.ExitCode -ne 0 -or $inst.Output -match '(?m)^(Error|ERROR)') {
            Add-Step $r 'Compile' 'FAIL' "install failed: $($inst.Output)"; $results.Add($r); continue
        }
    }
    $info = Invoke-Llvmup -Arguments @('info', $c.sel, '--json') -Path $hostPath
    try { $ij = $info.Output | ConvertFrom-Json; $r.toolchain = "$($ij.install_name)"; $root = "$($ij.root_path)" } catch { $root = '' }

    $dir = Join-Path $Work $id
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($k in $sources.Keys) { [IO.File]::WriteAllText((Join-Path $dir $k), $sources[$k], (New-Object Text.UTF8Encoding $false)) }

    if ($c.kind -eq 'msvc') {
        $v = Invoke-Tool $c $dir @($c.cc, '--version')
        Add-Step $r 'Compile' $(if ($v.ExitCode -eq 0) { 'PASS' } else { 'FAIL' }) $(if ($v.ExitCode -ne 0) { $v.Output })
        $o = Invoke-Tool $c $dir @($c.cc, '--target=x86_64-pc-windows-msvc', '-ffreestanding', '-nostdlibinc', '-c', 'lib.c', '-o', 'lib.obj')
        Add-Step $r 'Inspect' $(if ($o.ExitCode -eq 0 -and (Test-Path (Join-Path $dir 'lib.obj'))) { 'PASS' } else { 'FAIL' }) 'freestanding object only; hosted builds need Visual Studio/Windows SDK'
        $r.notes += 'official targets MSVC: Link/Execute/CMake need Visual Studio headers and libraries (not installed in a clean machine)'
        $r.seconds = [int]$sw.Elapsed.TotalSeconds; $results.Add($r); continue
    }

    # Compile + Link + Execute: C17
    $cc = Invoke-Tool $c $dir @($c.cc, '-std=c17', '-Wall', '-c', 'c17.c', '-o', 'c17.o')
    $cxx = Invoke-Tool $c $dir @($c.cxx, '-std=c++23', '-g', '-O1', '-c', 'cxx23.cpp', '-o', 'cxx23.o')
    Add-Step $r 'Compile' $(if ($cc.ExitCode -eq 0 -and $cxx.ExitCode -eq 0) { 'PASS' } else { 'FAIL' }) $(if ($cc.ExitCode) { "C: $($cc.Output)" } elseif ($cxx.ExitCode) { "C++: $($cxx.Output)" })
    $l1 = Invoke-Tool $c $dir @($c.cc, 'c17.o', '-o', 'c17.exe')
    $l2 = Invoke-Tool $c $dir @($c.cxx, 'cxx23.o', '-o', 'cxx23.exe')
    $linkOk = ($l1.ExitCode -eq 0 -and $l2.ExitCode -eq 0 -and (Test-Path (Join-Path $dir 'c17.exe')) -and (Test-Path (Join-Path $dir 'cxx23.exe')))
    Add-Step $r 'Link' $(if ($linkOk) { 'PASS' } else { 'FAIL' }) $(if (-not $linkOk) { "C: $($l1.Output)`nC++: $($l2.Output)" })

    if ($linkOk) {
        $pi = Get-PeInfo (Join-Path $dir 'cxx23.exe')
        $archOk = ($pi.Arch -eq $c.arch)
        Add-Step $r 'Inspect' $(if ($archOk) { 'PASS' } else { 'FAIL' }) "PE $($pi.Arch); imports: $($pi.Imports -join ', ')"
        Add-Step $r 'Debug' $(if (@($pi.Sections | Where-Object { $_ -like '/*' -or $_ -like '.debug*' -or $_ -eq '.stab' }).Count -gt 0) { 'PASS' } else { 'FAIL' }) "sections: $($pi.Sections -join ' ')"
        if ($c.exec) {
            $e1 = Invoke-Tool $c $dir @((Join-Path $dir 'c17.exe'))
            $e2 = Invoke-Tool $c $dir @((Join-Path $dir 'cxx23.exe'))
            $ok = ($e1.ExitCode -eq 0 -and $e1.Output -match 'C17 OK' -and $e2.ExitCode -eq 0 -and $e2.Output -match 'CXX23 OK')
            Add-Step $r 'Execute' $(if ($ok) { 'PASS' } else { 'FAIL' }) $(if (-not $ok) { "c17 rc=$($e1.ExitCode) $($e1.Output)`ncxx rc=$($e2.ExitCode) $($e2.Output)" })
        } else { Add-Step $r 'Execute' 'SKIP' "no $($c.arch) host" }
    }

    # Static library
    $s1 = Invoke-Tool $c $dir @($c.cc, '-c', 'lib.c', '-o', 'lib.o')
    $s2 = Invoke-Tool $c $dir @($c.ar, 'rcs', 'libfoo.a', 'lib.o')
    $s3 = Invoke-Tool $c $dir @($c.cc, 'uselib.c', '-L.', '-lfoo', '-o', 'uselib.exe')
    $stOk = ($s1.ExitCode -eq 0 -and $s2.ExitCode -eq 0 -and $s3.ExitCode -eq 0)
    if ($stOk -and $c.exec) { $x = Invoke-Tool $c $dir @((Join-Path $dir 'uselib.exe')); $stOk = ($x.ExitCode -eq 0 -and $x.Output -match 'STATIC 42') }
    Add-Step $r 'Static' $(if ($stOk) { 'PASS' } else { 'FAIL' }) $(if (-not $stOk) { "$($s1.Output) $($s2.Output) $($s3.Output)" })

    # DLL + import library
    $d1 = Invoke-Tool $c $dir @($c.cc, '-shared', 'dll.c', '-o', 'foo.dll', '-Wl,--out-implib,libfoo_dll.a')
    $d2 = Invoke-Tool $c $dir @($c.cc, 'usedll.c', '-L.', '-lfoo_dll', '-o', 'usedll.exe')
    $dOk = ($d1.ExitCode -eq 0 -and $d2.ExitCode -eq 0 -and (Test-Path (Join-Path $dir 'libfoo_dll.a')))
    if ($dOk -and $c.exec) { $x = Invoke-Tool $c $dir @((Join-Path $dir 'usedll.exe')); $dOk = ($x.ExitCode -eq 0 -and $x.Output -match 'DLL 7') }
    Add-Step $r 'Dll' $(if ($dOk) { 'PASS' } else { 'FAIL' }) $(if (-not $dOk) { "$($d1.Output) $($d2.Output)" })

    # Windows resource
    if ($c.rc) {
        $w1 = Invoke-Tool $c $dir @($c.rc, 'res.rc', '-O', 'coff', '-o', 'res.o')
        $w2 = if ($w1.ExitCode -eq 0) { Invoke-Tool $c $dir @($c.cc, 'userc.c', 'res.o', '-o', 'userc.exe') } else { $w1 }
        $rOk = ($w1.ExitCode -eq 0 -and $w2.ExitCode -eq 0 -and (Test-Path (Join-Path $dir 'userc.exe')) -and (Get-PeInfo (Join-Path $dir 'userc.exe')).HasResources)
        Add-Step $r 'Resource' $(if ($rOk) { 'PASS' } else { 'FAIL' }) $(if (-not $rOk) { "$($w1.Output) $($w2.Output)" })
    }

    # Header origin: every system include directory must be inside the toolchain root.
    $inc = Invoke-Tool $c $dir @($c.cxx, '-E', '-v', '-x', 'c++', '-std=c++23', 'empty.cpp', '-o', 'NUL')
    $dirs = @($inc.Output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[A-Za-z]:[\\/]' -and (Test-Path -LiteralPath $_ -PathType Container -ErrorAction SilentlyContinue) })
    $outside = @($dirs | Where-Object { $root -and -not ($_.Replace('/', '\').ToLowerInvariant().StartsWith($root.Replace('/', '\').ToLowerInvariant())) })
    Add-Step $r 'Headers' $(if ($dirs.Count -gt 0 -and $outside.Count -eq 0) { 'PASS' } else { 'FAIL' }) $(if ($outside.Count) { "outside toolchain: $($outside -join '; ')" } else { "$($dirs.Count) include dirs, all inside the toolchain" })

    # CMake + Ninja through the generated toolchain file
    if ($hasCMake -and $linkOk) {
        $tc = Join-Path $dir 'toolchain.cmake'
        $g = Invoke-Llvmup -Arguments (@('cmake-toolchain', $c.sel) + $c.cmakeArgs + @('--output', $tc)) -Path $cmakePath -Cwd $dir
        $cm1 = Invoke-Tool $c $dir @('cmake', '-S', $dir, '-B', (Join-Path $dir 'build'), '-G', 'Ninja', "-DCMAKE_TOOLCHAIN_FILE=$tc", '-DCMAKE_BUILD_TYPE=Release') $cmakePath
        $cm2 = if ($cm1.ExitCode -eq 0) { Invoke-Tool $c $dir @('cmake', '--build', (Join-Path $dir 'build')) $cmakePath } else { $cm1 }
        $cmOk = ($g.ExitCode -eq 0 -and $cm1.ExitCode -eq 0 -and $cm2.ExitCode -eq 0 -and (Test-Path (Join-Path $dir 'build\cm.exe')))
        if ($cmOk -and $c.exec) { $x = Invoke-Tool $c $dir @((Join-Path $dir 'build\cm.exe')); $cmOk = ($x.ExitCode -eq 0 -and $x.Output -match 'CXX23 OK') }
        Add-Step $r 'CMake' $(if ($cmOk) { 'PASS' } else { 'FAIL' }) $(if (-not $cmOk) { "$($g.Output)`n$($cm1.Output)`n$($cm2.Output)" })
    } elseif (-not $hasCMake) { $r.notes += '[CMake] cmake/ninja not found on the host PATH' }

    $r.seconds = [int]$sw.Elapsed.TotalSeconds
    $results.Add($r)
}

# ---------------------------------------------------------------- report
$lines = @('| Configuration | ' + ($steps -join ' | ') + ' |', '| --- | ' + (($steps | ForEach-Object { '---' }) -join ' | ') + ' |')
foreach ($r in $results) { $lines += "| $($r.id) ($($r.toolchain)) | " + (($steps | ForEach-Object { $r.steps[$_] }) -join ' | ') + ' |' }
$lines | ForEach-Object { Write-Host $_ }
foreach ($r in $results) { foreach ($n in $r.notes) { Write-Host "$($r.id): $n" -ForegroundColor DarkGray } }
if ($OutFile) {
    $json = [ordered]@{ date = (Get-Date).ToString('s'); os = [Environment]::OSVersion.VersionString; ps = $PSVersionTable.PSVersion.ToString(); home = $LlvmHome; results = $results }
    ($json | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $OutFile -Encoding UTF8
}
$failed = @($results | Where-Object { $_.steps.Values -contains 'FAIL' }).Count
exit $(if ($failed) { 1 } else { 0 })
