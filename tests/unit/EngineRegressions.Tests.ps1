$ErrorActionPreference = 'Stop'

# Regression tests for extractor discovery, verification policy, locked installs, CMake generation,
# and the llvmup.cmd launcher. Offline: every network URL is unreachable on purpose.
Describe 'LLVMUP engine regressions' {
    BeforeAll {
        $script:repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pwshDir = Join-Path (Join-Path $script:repoRoot 'libexec') 'pwsh'
        Import-Module (Join-Path $script:repoRoot 'Llvm-Functions.psm1') -Force -Global -DisableNameChecking
        foreach ($m in @('Llvm-Extractor', 'Llvm-Downloader', 'Llvm-Verifier', 'Llvm-Recipes', 'Llvm-Manifest', 'Llvm-Installer', 'Llvm-CMake', 'Llvm-Environment')) {
            Import-Module (Join-Path $pwshDir "$m.psm1") -Force -Global -DisableNameChecking
        }
        $script:isWin = ($env:OS -eq 'Windows_NT')
        $script:savedPath = $env:PATH
        $script:saved = @{}
        foreach ($v in @('LLVMUP_7Z_PATH', 'LLVMUP_TAR_PATH', 'LLVMUP_WINLIBS_RELEASES_FILE', 'LLVM_HOME', 'LLVM_TOOLCHAINS_DIR', 'LLVMUP_CACHE_DIR', 'LLVMUP_VERIFY_POLICY', 'LLVMUP_7Z_TAR_STRATEGY')) {
            $script:saved[$v] = [Environment]::GetEnvironmentVariable($v, 'Process')
        }

        function New-FakeTool {
            param([string]$Dir, [string]$Name, [string[]]$Lines)
            $null = New-Item -ItemType Directory -Path $Dir -Force
            $body = @('@echo off') + @($Lines | ForEach-Object { "echo $_" })
            $path = Join-Path $Dir "$Name.cmd"
            Set-Content -LiteralPath $path -Value $body -Encoding Ascii
            return $path
        }
    }

    AfterAll {
        # Do not leak globally imported modules (e.g. the real Get-UserHome) into later test files.
        foreach ($m in @('Llvm-Installer', 'Llvm-CMake', 'Llvm-Environment', 'Llvm-Verifier', 'Llvm-Recipes', 'Llvm-Manifest', 'Llvm-Extractor',
                         'Llvm-Runner', 'Llvm-Resolver', 'Llvm-ConfigEngine', 'Llvm-Downloader', 'Llvm-Selection', 'Llvm-Functions', 'Llvm-Functions-Core', 'Get-UserHome')) {
            Remove-Module -Name $m -Force -ErrorAction SilentlyContinue
        }
    }

    AfterEach {
        $env:PATH = $script:savedPath
        foreach ($kv in $script:saved.GetEnumerator()) {
            if ($null -eq $kv.Value) { Remove-Item -LiteralPath "Env:$($kv.Key)" -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, 'Process') }
        }
    }

    Context '7-Zip and tar discovery' {
        It 'prefers the newest modern 7-Zip over an ancient one earlier on PATH' -Skip:($env:OS -ne 'Windows_NT') {
            $old = Join-Path $TestDrive 'old7z'
            $new = Join-Path $TestDrive 'new7z'
            New-FakeTool -Dir $old -Name '7z' -Lines @('7-Zip 4.65  Copyright (c) 1999-2009 Igor Pavlov', 'Formats:', '0  C   7z      7z', '0  C   Tar     tar', '0  C   Zip     zip') | Out-Null
            New-FakeTool -Dir $new -Name '7z' -Lines @('7-Zip 23.01 (x64) : Copyright (c) 1999-2023 Igor Pavlov', 'Formats:', ' 0 C  7z  7z', ' 0 C  tar tar', ' 0 C  xz  xz txz', ' 0 C  zip zip', ' 0 C  Nsis nsis') | Out-Null
            $env:PATH = "$old;$new;$($env:SystemRoot)\System32"
            $all = @(Find-Llvm7Zip -All)
            $best = Find-Llvm7Zip
            if ($all.Count -eq 2) {
                $best.version | Should -Be '23.01'
                $best.modern | Should -BeTrue
                $best.supports_xz | Should -BeTrue
            } else {
                # A real 7-Zip installation was also found; the ancient one must still lose.
                $best.version | Should -Not -Be '4.65'
            }
            ($all | Where-Object version -eq '4.65').supports_xz | Should -BeFalse
            ($all | Where-Object version -eq '4.65').modern | Should -BeFalse
        }

        It 'honors LLVMUP_7Z_PATH and fails clearly when it does not exist' {
            $env:LLVMUP_7Z_PATH = Join-Path $TestDrive 'missing\7z.exe'
            { Find-Llvm7Zip } | Should -Throw '*does not exist*'
        }

        It 'detects xz support from the tar build instead of assuming it' -Skip:($env:OS -ne 'Windows_NT') {
            $inbox = New-FakeTool -Dir (Join-Path $TestDrive 'bsd1') -Name 'tar' -Lines @('bsdtar 3.5.2 - libarchive 3.5.2 zlib/1.2.5.f-ipp')
            $full = New-FakeTool -Dir (Join-Path $TestDrive 'bsd2') -Name 'tar' -Lines @('bsdtar 3.7.2 - libarchive 3.7.2 zlib/1.3 liblzma/5.4.1 bz2lib/1.0.8 libzstd/1.5.5')
            (Get-LlvmTarProbe -Path $inbox).supports_xz | Should -BeFalse
            (Get-LlvmTarProbe -Path $full).supports_xz | Should -BeTrue
            (Get-LlvmTarProbe -Path $full).supports_zstd | Should -BeTrue
        }
    }

    Context 'Extractor selection never silently substitutes an explicit choice' {
        BeforeAll {
            $script:noXzTar = [pscustomobject]@{ available = $true; path = 'tar'; flavor = 'bsdtar'; supports_gz = $true; supports_xz = $false; supports_zstd = $false; extra_args = @() }
            $script:old7z = [pscustomobject]@{ available = $true; path = '7z'; version = '4.65'; modern = $false; supports_xz = $false; supports_7z = $true; supports_zip = $true; supports_tar = $true; supports_nsis = $false }
            $script:new7z = [pscustomobject]@{ available = $true; path = '7z'; version = '23.01'; modern = $true; supports_xz = $true; supports_7z = $true; supports_zip = $true; supports_tar = $true; supports_nsis = $true }
            $script:none7z = [pscustomobject]@{ available = $false; path = $null; version = ''; modern = $false; supports_xz = $false; supports_7z = $false; supports_zip = $false; supports_tar = $false; supports_nsis = $false }
            $script:msi = [pscustomobject]@{ available = $false; path = $null }
        }

        It 'auto picks modern 7-Zip for .tar.xz and refuses tar without xz' {
            $caps = [pscustomobject]@{ sevenzip = $script:new7z; tar = $script:noXzTar; msi = $script:msi }
            Resolve-LlvmExtractorChoice -Format 'tar.xz' -Extractor 'auto' -Caps $caps | Should -Be '7z'
            { Resolve-LlvmExtractorChoice -Format 'tar.xz' -Extractor 'tar' -Caps $caps } | Should -Throw '*cannot decompress xz*'
        }

        It 'reports a clear error when no backend can read .tar.xz' {
            $caps = [pscustomobject]@{ sevenzip = $script:none7z; tar = $script:noXzTar; msi = $script:msi }
            { Resolve-LlvmExtractorChoice -Format 'tar.xz' -Extractor 'auto' -Caps $caps } | Should -Throw '*inbox tar.exe lacks xz*'
        }

        It 'refuses an ancient 7-Zip for modern .7z archives and a missing 7-Zip when explicitly requested' {
            $caps = [pscustomobject]@{ sevenzip = $script:old7z; tar = $script:noXzTar; msi = $script:msi }
            { Resolve-LlvmExtractorChoice -Format '7z' -Extractor 'auto' -Caps $caps } | Should -Throw '*too old*'
            $caps2 = [pscustomobject]@{ sevenzip = $script:none7z; tar = $script:noXzTar; msi = $script:msi }
            { Resolve-LlvmExtractorChoice -Format 'zip' -Extractor '7z' -Caps $caps2 } | Should -Throw "*'7z' is not available*"
            Resolve-LlvmExtractorChoice -Format 'zip' -Extractor 'auto' -Caps $caps2 | Should -Be 'zip'
        }

        It 'round-trips a .tar.xz through both 7-Zip strategies and rejects corruption without leaving staging' {
            $sz = Find-Llvm7Zip
            if (-not ($sz.available -and $sz.modern -and $sz.supports_xz)) {
                Set-ItResult -Skipped -Because 'no modern 7-Zip with xz support is available'
                return
            }
            $src = Join-Path $TestDrive 'xzsrc'
            $null = New-Item -ItemType Directory -Path (Join-Path $src 'pkg\bin') -Force
            $null = New-Item -ItemType Directory -Path (Join-Path $src 'pkg\with space') -Force
            1..30 | ForEach-Object { [IO.File]::WriteAllBytes((Join-Path $src "pkg\bin\f$_.bin"), [byte[]](1..200 | ForEach-Object { $_ % 256 })) }
            Set-Content -LiteralPath (Join-Path $src 'pkg\with space\note.txt') -Value 'hello' -Encoding Ascii
            $tar = Join-Path $TestDrive 'pkg.tar'
            $xz = Join-Path $TestDrive 'pkg.tar.xz'
            Push-Location $src
            try {
                & $sz.path a -ttar $tar 'pkg' -bd *> $null
                & $sz.path a -txz $xz $tar -bd *> $null
            } finally { Pop-Location }

            foreach ($strategy in @('stream', 'pipe', 'temp')) {
                $env:LLVMUP_7Z_TAR_STRATEGY = $strategy
                $dest = Join-Path $TestDrive "out-$strategy"
                $r = Invoke-LlvmArchiveExtract -ArchivePath $xz -DestinationPath $dest -Extractor '7z'
                $r.strategy | Should -Be $strategy
                (Get-ChildItem -LiteralPath (Join-Path $dest 'bin') -File).Count | Should -Be 30
                Get-Content -LiteralPath (Join-Path $dest 'with space\note.txt') | Should -Be 'hello'
            }

            $bytes = [IO.File]::ReadAllBytes($xz)
            $mid = [int]($bytes.Length / 2)
            $bytes[$mid] = $bytes[$mid] -bxor 0xFF
            $bad = Join-Path $TestDrive 'bad.tar.xz'
            [IO.File]::WriteAllBytes($bad, $bytes)
            $env:LLVMUP_7Z_TAR_STRATEGY = 'stream'
            { Invoke-LlvmArchiveExtract -ArchivePath $bad -DestinationPath (Join-Path $TestDrive 'out-bad') -Extractor '7z' } | Should -Throw
            Test-Path -LiteralPath (Join-Path $TestDrive 'out-bad') | Should -BeFalse
            @(Get-ChildItem -LiteralPath $TestDrive -Directory -Filter 'out-bad.*').Count | Should -Be 0
        }

        It 'rejects ZIP entries that escape the destination before writing anything' {
            Add-Type -AssemblyName System.IO.Compression
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zipPath = Join-Path $TestDrive 'evil.zip'
            $fs = [IO.File]::Open($zipPath, 'Create')
            $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
            foreach ($n in @('pkg/bin/ok.txt', 'pkg/../../evil.txt')) {
                $e = $zip.CreateEntry($n)
                $w = New-Object IO.StreamWriter($e.Open()); $w.Write('x'); $w.Dispose()
            }
            $zip.Dispose(); $fs.Dispose()
            { Invoke-LlvmArchiveExtract -ArchivePath $zipPath -DestinationPath (Join-Path $TestDrive 'evil-out') -Extractor 'zip' } | Should -Throw '*Unsafe ZIP*'
            Test-Path -LiteralPath (Join-Path $TestDrive 'evil-out') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path (Split-Path $TestDrive -Parent) 'evil.txt') | Should -BeFalse
        }

        It 'extracts ZIP entries whose full path exceeds MAX_PATH (Windows PowerShell 5.1 has no long path support)' -Skip:($env:OS -ne 'Windows_NT') {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zipPath = Join-Path $TestDrive 'deep.zip'
            $deep = (1..12 | ForEach-Object { 'segment_number_' + $_ }) -join '/'
            $entryName = "root/$deep/constructor_destructor_no_store_hash_fn_imps.hpp"
            $fs = [IO.File]::Open($zipPath, 'Create')
            $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
            $e = $zip.CreateEntry($entryName)
            $w = New-Object IO.StreamWriter($e.Open()); $w.Write('deep'); $w.Dispose()
            $zip.Dispose(); $fs.Dispose()

            $dest = Join-Path $TestDrive 'deep-out'
            $expected = Join-Path $dest ($entryName.Substring(5).Replace('/', '\'))
            $expected.Length | Should -BeGreaterThan 260
            $null = Invoke-LlvmArchiveExtract -ArchivePath $zipPath -DestinationPath $dest -Extractor 'zip'
            $content = [IO.File]::ReadAllText('\\?\' + $expected.Replace('\\?\', ''))
            $content | Should -Be 'deep'
        }
    }

    Context 'Verification policy' {
        It 'warns under the warn policy when nothing authenticates the download' {
            $artifact = Join-Path $TestDrive 'a.zip'
            Set-Content -LiteralPath $artifact -Value 'payload' -Encoding Ascii
            $plan = [ordered]@{
                provider = 'winlibs'
                recipe = (Get-LlvmRecipe -Provider 'winlibs')
                asset = [ordered]@{ name = 'a.zip'; digest = ''; format = 'zip' }
                verification_assets = [ordered]@{ sha256 = $null; sha512 = $null; sig = $null; jsonl = $null }
            }
            $r = Invoke-LlvmAssetVerify -ArtifactPath $artifact -Plan $plan -TempPath $TestDrive -Policy 'warn' -WarningVariable warns -WarningAction SilentlyContinue
            @($r.methods) | Should -Contain 'unverified'
            @($warns).Count | Should -BeGreaterThan 0
            ($warns -join ' ') | Should -Match 'could not be verified'

            $sha = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
            $plan.asset.digest = "sha256:$sha"
            $r2 = Invoke-LlvmAssetVerify -ArtifactPath $artifact -Plan $plan -TempPath $TestDrive -Policy 'warn' -WarningVariable warns2 -WarningAction SilentlyContinue
            $r2.checksum | Should -Be 'valid'
            @($r2.methods) | Should -Contain 'checksum-only'
            ($warns2 -join ' ') | Should -Match 'origin is not authenticated'

            $r3 = Invoke-LlvmAssetVerify -ArtifactPath $artifact -Plan $plan -TempPath $TestDrive -Policy 'warn' -Quiet -WarningVariable warns3 -WarningAction SilentlyContinue
            @($warns3).Count | Should -Be 0
        }

        It 'does not leave GH_TOKEN behind in the session' {
            $before = [Environment]::GetEnvironmentVariable('GH_TOKEN', 'Process')
            $artifact = Join-Path $TestDrive 'b.zip'
            Set-Content -LiteralPath $artifact -Value 'payload' -Encoding Ascii
            $plan = [ordered]@{
                provider = 'official'
                recipe = (Get-LlvmRecipe -Provider 'official')
                asset = [ordered]@{ name = 'b.zip'; digest = ''; format = 'zip' }
                verification_assets = [ordered]@{ sha256 = $null; sha512 = $null; sig = $null; jsonl = $null }
            }
            $null = Invoke-LlvmAssetVerify -ArtifactPath $artifact -Plan $plan -TempPath $TestDrive -Policy 'warn' -Quiet
            [Environment]::GetEnvironmentVariable('GH_TOKEN', 'Process') | Should -Be $before
        }
    }

    Context 'Locked installs are enforced before any download' {
        BeforeEach {
            $script:lockHome = Join-Path $TestDrive ("lock-" + [guid]::NewGuid().ToString('N').Substring(0, 6))
            $env:LLVM_HOME = $script:lockHome
            $env:LLVM_TOOLCHAINS_DIR = Join-Path $script:lockHome 'toolchains'
            $env:LLVMUP_CACHE_DIR = Join-Path $script:lockHome 'cache'
            $releases = @(@{
                tag_name = '16.2.0posix-23.1.3-14.0.0-ucrt-r3'; prerelease = $false; draft = $false
                assets = @(@{ name = 'winlibs-x86_64-posix-seh-gcc-16.2.0-llvm-23.1.3-mingw-w64ucrt-14.0.0-r3.zip'; browser_download_url = 'https://example.invalid/w.zip'; size = 1; digest = 'sha256:' + ('a' * 64) })
            })
            $env:LLVMUP_WINLIBS_RELEASES_FILE = Join-Path $TestDrive 'wl-lock.json'
            Set-Content -LiteralPath $env:LLVMUP_WINLIBS_RELEASES_FILE -Value (ConvertTo-Json -InputObject $releases -Depth 6) -Encoding UTF8
            $script:entry = @{
                provider = 'winlibs'; release = '16.2.0posix-23.1.3-14.0.0-ucrt-r3'; verify_policy = 'warn'
                asset = @{ name = 'winlibs-x86_64-posix-seh-gcc-16.2.0-llvm-23.1.3-mingw-w64ucrt-14.0.0-r3.zip'; digest = 'sha256:' + ('b' * 64) }
            }
        }

        It 'fails on a digest that differs from the lockfile without downloading' {
            { Invoke-LlvmInstallPrebuiltFromRecipe -Provider winlibs -ReleaseTag $script:entry.release -Platform windows -Arch x64 -LockedEntry $script:entry -Quiet -MaxRetries 1 } | Should -Throw '*Locked digest*'
            Test-Path -LiteralPath $env:LLVMUP_CACHE_DIR | Should -BeFalse
            @(Get-ChildItem -LiteralPath $env:LLVM_TOOLCHAINS_DIR -ErrorAction SilentlyContinue).Count | Should -Be 0
        }

        It 'refuses a weaker verification policy than the lockfile' {
            $script:entry.verify_policy = 'strict'
            $script:entry.asset.digest = 'sha256:' + ('a' * 64)
            { Invoke-LlvmInstallPrebuiltFromRecipe -Provider winlibs -ReleaseTag $script:entry.release -Platform windows -Arch x64 -VerifyPolicy warn -LockedEntry $script:entry -Quiet -MaxRetries 1 } | Should -Throw '*weaker than the locked policy*'
        }

        It 'uses canonical ids that include the host architecture' {
            $plan = Invoke-LlvmInstallPrebuiltFromRecipe -Provider winlibs -ReleaseTag $script:entry.release -Platform windows -Arch x64 -ResolveOnly -Quiet
            $plan.canonical_id | Should -Be 'winlibs-16.2.0posix-23.1.3-14.0.0-ucrt-r3-x64'
        }
    }

    Context 'Asset selection respects locally extractable formats' {
        BeforeAll {
            $script:offRel = @(@{
                tag_name = 'llvmorg-23.1.6'; prerelease = $false; draft = $false
                assets = @(
                    @{ name = 'clang+llvm-23.1.6-x86_64-pc-windows-msvc.tar.xz'; browser_download_url = 'https://example.invalid/a.tar.xz'; size = 901 }
                    @{ name = 'clang+llvm-23.1.6-x86_64-pc-windows-msvc.tar.zst'; browser_download_url = 'https://example.invalid/a.tar.zst'; size = 276 }
                    @{ name = 'clang+llvm-23.1.6-x86_64-pc-windows-msvc.tar.zst.jsonl'; browser_download_url = 'https://example.invalid/a.jsonl'; size = 1 }
                    @{ name = 'LLVM-23.1.6-win64.msi'; browser_download_url = 'https://example.invalid/a.msi'; size = 639 }
                )
            })
            $script:wlRel = @(@{
                tag_name = '16.2.0posix-23.1.3-14.0.0-ucrt-r3'; prerelease = $false; draft = $false
                assets = @(
                    @{ name = 'winlibs-x86_64-posix-seh-gcc-16.2.0-llvm-23.1.3-mingw-w64ucrt-14.0.0-r3.zip'; browser_download_url = 'https://example.invalid/w.zip'; size = 423 }
                    @{ name = 'winlibs-x86_64-posix-seh-gcc-16.2.0-llvm-23.1.3-mingw-w64ucrt-14.0.0-r3.7z'; browser_download_url = 'https://example.invalid/w.7z'; size = 188 }
                    @{ name = 'winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r3.7z'; browser_download_url = 'https://example.invalid/gcc-only.7z'; size = 111 }
                )
            })
        }

        It 'prefers the smaller .tar.zst only when a zstd backend exists' {
            $p1 = Resolve-LlvmRecipeInstallPlan -Provider official -Releases $script:offRel -VersionExpression '23' -Platform windows -Arch x64 -ArchiveOnly -AvailableFormats @('zip', '7z', 'tar.xz')
            $p1.asset.name | Should -Match '\.tar\.xz$'
            $p2 = Resolve-LlvmRecipeInstallPlan -Provider official -Releases $script:offRel -VersionExpression '23' -Platform windows -Arch x64 -ArchiveOnly -AvailableFormats @('zip', 'tar.xz', 'tar.zst')
            $p2.asset.name | Should -Match '\.tar\.zst$'
            $p2.verification_assets.jsonl | Should -Not -BeNullOrEmpty
            { Resolve-LlvmRecipeInstallPlan -Provider official -Releases $script:offRel -VersionExpression '23' -Platform windows -Arch x64 -ArchiveOnly -AvailableFormats @('zip') } | Should -Throw '*No stable release*'
        }

        It 'prefers WinLibs .7z with a modern 7-Zip, falls back to .zip, and never picks GCC-only bundles' {
            $p7 = Resolve-LlvmRecipeInstallPlan -Provider winlibs -Releases $script:wlRel -Platform windows -Arch x64 -AvailableFormats @('zip', '7z')
            $p7.asset.name | Should -Match 'llvm-23\.1\.3.*\.7z$'
            $pz = Resolve-LlvmRecipeInstallPlan -Provider winlibs -Releases $script:wlRel -Platform windows -Arch x64 -AvailableFormats @('zip', 'tar.xz')
            $pz.asset.name | Should -Match 'llvm-23\.1\.3.*\.zip$'
        }

        It 'uses a portable format baseline when resolving for another host' {
            $other = if ($env:OS -eq 'Windows_NT') { 'linux' } else { 'windows' }
            $f = Get-LlvmPlanFormats -HostOs $other -HostArch x64
            $f | Should -Contain 'tar.xz'
            $f | Should -Not -Contain 'tar.zst'
        }
    }

    Context 'CMake toolchain generation' {
        It 'does not declare CMAKE_SYSTEM_NAME for native builds but does for cross targets' -Skip:($env:OS -ne 'Windows_NT') {
            $root = Join-Path $TestDrive 'mw'
            $bin = Join-Path $root 'bin'
            $null = New-Item -ItemType Directory -Path $bin -Force
            $cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
            foreach ($n in @('clang.exe', 'clang++.exe', 'x86_64-w64-mingw32-clang.exe', 'x86_64-w64-mingw32-clang++.exe', 'aarch64-w64-mingw32-clang.exe', 'aarch64-w64-mingw32-clang++.exe', 'llvm-ar.exe')) {
                Copy-Item -LiteralPath $cmdExe -Destination (Join-Path $bin $n)
            }
            $m = New-LlvmToolchainManifest -Id 'lm' -InstallName 'lm' -Provider 'llvm-mingw' -HostOs 'windows' -HostArch 'x64' -SupportedTargets @('x86_64-w64-mingw32', 'aarch64-w64-mingw32') -DefaultTarget 'x86_64-w64-mingw32' -Variant @{ crt = 'ucrt'; cxx_stdlib = 'libc++'; default_compiler = 'clang' } -Root $root
            $m['root_path'] = $root
            $native = New-LlvmCMakeToolchainFile -Manifest $m -Target 'x86_64-w64-mingw32'
            $native | Should -Not -Match 'CMAKE_SYSTEM_NAME'
            $native | Should -Match 'x86_64-w64-mingw32-clang\.exe'
            $cross = New-LlvmCMakeToolchainFile -Manifest $m -Target 'aarch64-w64-mingw32'
            $cross | Should -Match 'set\(CMAKE_SYSTEM_NAME Windows\)'
            $cross | Should -Match 'set\(CMAKE_SYSTEM_PROCESSOR ARM64\)'
        }
    }

    Context 'Installation lock and interrupted operations' {
        It 'reclaims a lock file left by a dead process but refuses a held lock' {
            $tc = Join-Path $TestDrive 'lock-tc'
            $null = New-Item -ItemType Directory -Path $tc -Force
            Set-Content -LiteralPath (Join-Path $tc '.tc1.llvmup.lock') -Value 'pid=999999'
            $h = Enter-LlvmToolchainLock -ToolchainsPath $tc -InstallName 'tc1'
            try {
                { Enter-LlvmToolchainLock -ToolchainsPath $tc -InstallName 'tc1' } | Should -Throw '*Another llvmup operation*'
            } finally { Exit-LlvmToolchainLock -LockHandle $h }
            Test-Path -LiteralPath (Join-Path $tc '.tc1.llvmup.lock') | Should -BeFalse
            $h2 = Enter-LlvmToolchainLock -ToolchainsPath $tc -InstallName 'tc1'
            Exit-LlvmToolchainLock -LockHandle $h2
        }

        It 'restores the backup of an interrupted replacement and removes staging leftovers' {
            $tc = Join-Path $TestDrive 'repair-tc'
            $g = 'a' * 32
            $backup = Join-Path $tc "tc2.backup-$g"
            $staging = Join-Path $tc "tc2.installing-$g.raw-$g"
            $other = Join-Path $tc 'tc2-other'
            foreach ($d in @($backup, $staging, $other)) { $null = New-Item -ItemType Directory -Path (Join-Path $d 'bin') -Force }
            $h = Enter-LlvmToolchainLock -ToolchainsPath $tc -InstallName 'tc2' 3>$null
            Exit-LlvmToolchainLock -LockHandle $h
            Test-Path -LiteralPath (Join-Path $tc 'tc2\bin') | Should -BeTrue
            Test-Path -LiteralPath $backup | Should -BeFalse
            Test-Path -LiteralPath $staging | Should -BeFalse
            Test-Path -LiteralPath $other | Should -BeTrue
        }
    }

    Context '7-Zip streaming failure handling' {
        It 'does not deadlock when the tar side exits early and reports its error' -Skip:($env:OS -ne 'Windows_NT') {
            $dir = Join-Path $TestDrive 'fake7z-stream'
            $null = New-Item -ItemType Directory -Path $dir -Force
            $fake = Join-Path $dir '7z.cmd'
            # -si (tar side): fail at once. -so (decompressor): write forever.
            Set-Content -LiteralPath $fake -Encoding Ascii -Value @(
                '@echo off',
                'echo %* | findstr /c:"-si" >nul && (echo ERROR: Headers Error 1>&2 & exit /b 2)',
                ':loop',
                'echo 0123456789012345678901234567890123456789012345678901234567890123456789',
                'goto loop')
            $module = Join-Path $script:repoRoot 'libexec\pwsh\Llvm-Extractor.psm1'
            $job = Start-Job -ScriptBlock {
                param($m, $f, $o)
                $mod = Import-Module $m -DisableNameChecking -PassThru
                & $mod { param($f, $o) try { Invoke-Llvm7ZipStreamTar -SevenZipPath $f -ArchivePath 'x.tar.zst' -OutputDir $o; 'no-error' } catch { "error: $($_.Exception.Message)" } } $f $o
            } -ArgumentList $module, $fake, (Join-Path $dir 'out')
            $finished = Wait-Job -Job $job -Timeout 60
            if (-not $finished) { Stop-Job $job; Remove-Job $job -Force; throw 'Invoke-Llvm7ZipStreamTar deadlocked' }
            $result = Receive-Job $job; Remove-Job $job -Force
            "$result" | Should -Match 'tar extraction failed with exit code 2: ERROR: Headers Error'
        }
    }

    Context '7-Zip streaming end of archive' {
        It 'accepts zero padding after the tar end marker and rejects real data the tar side ignored' -Skip:($env:OS -ne 'Windows_NT') {
            $module = Join-Path $script:repoRoot 'libexec\pwsh\Llvm-Extractor.psm1'
            $run = {
                param([int]$Byte)
                $dir = Join-Path $TestDrive "fake7z-eoa-$Byte"
                $null = New-Item -ItemType Directory -Path $dir -Force
                $fake = Join-Path $dir '7z.cmd'
                # -si: finish successfully without reading (like 7-Zip at the end-of-archive marker).
                # -so: write 3 MiB of the given byte value.
                Set-Content -LiteralPath $fake -Encoding Ascii -Value @(
                    '@echo off',
                    "echo %* | findstr /c:`"-si`" >nul && (powershell -NoProfile -Command `"`$i = [Console]::OpenStandardInput(); `$b = New-Object byte[] 65536; [void]`$i.Read(`$b, 0, 65536)`" & exit /b 0)",
                    "powershell -NoProfile -Command `"`$b = New-Object byte[] 3145728; if ($Byte) { for (`$i = 0; `$i -lt `$b.Length; `$i++) { `$b[`$i] = $Byte } }; `$o = [Console]::OpenStandardOutput(); `$o.Write(`$b, 0, `$b.Length); `$o.Flush()`"")
                # The tar side 'extracted' something before finishing, as 7-Zip does before the end marker.
                $null = New-Item -ItemType Directory -Path (Join-Path $dir 'out') -Force
                Set-Content -LiteralPath (Join-Path (Join-Path $dir 'out') 'f.txt') -Value x
                $job = Start-Job -ScriptBlock {
                    param($m, $f, $o)
                    $mod = Import-Module $m -DisableNameChecking -PassThru
                    & $mod { param($f, $o) try { Invoke-Llvm7ZipStreamTar -SevenZipPath $f -ArchivePath 'x.tar.zst' -OutputDir $o; 'no-error' } catch { "error: $($_.Exception.Message)" } } $f $o
                } -ArgumentList $module, $fake, (Join-Path $dir 'out')
                if (-not (Wait-Job -Job $job -Timeout 90)) { Stop-Job $job; Remove-Job $job -Force; throw 'stream deadlocked' }
                $r = "$(Receive-Job $job)"; Remove-Job $job -Force
                return $r
            }
            & $run 0 | Should -Be 'no-error'
            & $run 65 | Should -Match 'non-padding data'
        }

        It 'marks a tar side that exits without reading so the cmd.exe pipe can take over' -Skip:($env:OS -ne 'Windows_NT') {
            $dir = Join-Path $TestDrive 'fake7z-noread'
            $null = New-Item -ItemType Directory -Path $dir -Force
            $fake = Join-Path $dir '7z.cmd'
            Set-Content -LiteralPath $fake -Encoding Ascii -Value @('@echo off', 'echo %* | findstr /c:"-si" >nul && exit /b 0', ':loop', 'echo data', 'goto loop')
            $module = Join-Path $script:repoRoot 'libexec\pwsh\Llvm-Extractor.psm1'
            $job = Start-Job -ScriptBlock {
                param($m, $f, $o)
                $mod = Import-Module $m -DisableNameChecking -PassThru
                & $mod { param($f, $o) try { Invoke-Llvm7ZipStreamTar -SevenZipPath $f -ArchivePath 'x.tar.zst' -OutputDir $o; 'no-error' } catch { "error: $($_.Exception.Message)" } } $f $o
            } -ArgumentList $module, $fake, (Join-Path $dir 'out')
            if (-not (Wait-Job -Job $job -Timeout 60)) { Stop-Job $job; Remove-Job $job -Force; throw 'stream deadlocked' }
            $r = "$(Receive-Job $job)"; Remove-Job $job -Force
            $r | Should -Match 'LLVMUP_7Z_TAR_SIDE_DID_NOT_READ'
        }
    }

    Context 'Missing extraction backends' {
        It 'explains that a matching asset exists but cannot be unpacked instead of claiming no release matches' {
            Remove-Item Env:LLVMUP_ASSET_FORMATS -ErrorAction SilentlyContinue
            $releases = @((Get-Content -LiteralPath (Join-Path $script:repoRoot 'tests\fixtures\releases\official.json') -Raw | ConvertFrom-Json) | ForEach-Object { $_ })
            Mock Get-LlvmPlanFormats -ModuleName Llvm-Recipes { @('zip') }
            { Resolve-LlvmRecipeInstallPlan -Provider official -Releases $releases -VersionExpression '23' -Platform windows -Arch x64 -ArchiveOnly } |
                Should -Throw "*has a matching asset (clang+llvm-23.1.6-x86_64-pc-windows-msvc.tar.*), but no local extractor can unpack it*Install 7-Zip*"
            { Resolve-LlvmRecipeInstallPlan -Provider official -Releases $releases -VersionExpression '99' -Platform windows -Arch x64 -ArchiveOnly } |
                Should -Throw "*No stable release of provider 'official' matches '99'*"
        }
    }

    Context 'Environment delta details' {
        BeforeAll {
            $script:mkRoot = {
                param([string]$Name)
                $r = Join-Path $TestDrive $Name
                $null = New-Item -ItemType Directory -Path (Join-Path $r 'bin') -Force
                foreach ($n in @('clang.exe', 'clang++.exe', 'gcc.exe', 'g++.exe')) { Set-Content -LiteralPath (Join-Path $r "bin\$n") -Value '' }
                $m = New-LlvmToolchainManifest -Id 'wl' -InstallName $Name -Provider 'winlibs' -LlvmVersion '23.1.3' -HostOs 'windows' -HostArch 'x64' -Variant @{ crt = 'ucrt'; default_compiler = 'clang' } -Root $r
                $m['root_path'] = $r
                return $m
            }
        }

        It 'puts the selected target runtime directory of llvm-mingw before bin/' {
            $r = Join-Path $TestDrive 'lm-rt'
            foreach ($d in @('bin', 'i686-w64-mingw32\bin', 'x86_64-w64-mingw32\bin')) { $null = New-Item -ItemType Directory -Path (Join-Path $r $d) -Force }
            Set-Content -LiteralPath (Join-Path $r 'bin\clang.exe') -Value ''
            $m = New-LlvmToolchainManifest -Id 'lm' -InstallName 'lm-rt' -Provider 'llvm-mingw' -LlvmVersion '23.1.6' -SupportedTargets @('x86_64-w64-mingw32', 'i686-w64-mingw32') -DefaultTarget 'x86_64-w64-mingw32' -Variant @{ crt = 'ucrt'; default_compiler = 'clang' } -Root $r
            $m['root_path'] = $r
            $d = Get-LlvmEnvironmentDelta -Manifest $m -Target 'i686-w64-mingw32'
            @($d.prepend_path) | Should -Be @((Join-Path $r 'i686-w64-mingw32\bin'), (Join-Path $r 'bin'))
            $wl = & $script:mkRoot 'wl-rt'
            @((Get-LlvmEnvironmentDelta -Manifest $wl).prepend_path) | Should -Be @((Join-Path $wl.root_path 'bin'))
        }

        It 'exports both the historical and the llvm-sys LLVM_SYS_NNN_PREFIX names' {
            $m = & $script:mkRoot 'wl-nosp'
            $d = Get-LlvmEnvironmentDelta -Manifest $m
            $d.set['LLVM_SYS_230_PREFIX'] | Should -Be $m.root_path
            $d.set['LLVM_SYS_231_PREFIX'] | Should -Be $m.root_path
        }

        It 'warns about WinLibs GCC under a path with spaces only when GCC is selected' {
            $m = & $script:mkRoot 'wl with space'
            $gccWarn = @(Get-LlvmEnvironmentDelta -Manifest $m -Compiler gcc 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $gccWarn.Count | Should -Be 1
            "$($gccWarn[0])" | Should -Match 'contains whitespace \(affects: gcc\)'
            $clangWarn = @(Get-LlvmEnvironmentDelta -Manifest $m -Compiler clang 3>&1 | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $clangWarn.Count | Should -Be 0
            @(Get-LlvmRecipePathConstraintWarnings -Provider 'winlibs' -RootPath 'C:\nospace\wl').Count | Should -Be 0
            @(Get-LlvmRecipePathConstraintWarnings -Provider 'official' -RootPath 'C:\with space\x').Count | Should -Be 0
        }
    }

    Context 'llvmup.cmd launcher' {
        BeforeAll {
            $script:launcher = Join-Path $script:repoRoot 'llvmup.cmd'
            $script:lhome = Join-Path $TestDrive 'launcher-home'
            $script:ext = Join-Path $TestDrive 'ext-tc'
            $null = New-Item -ItemType Directory -Path (Join-Path $script:ext 'bin') -Force
            Set-Content -LiteralPath (Join-Path $script:ext 'bin\clang.cmd') -Encoding Ascii -Value @(
                '@echo off', 'echo first', 'ping -n 3 127.0.0.1 >nul', 'echo second', 'echo arg=[%~1]', 'exit /b 7')
            Copy-Item -LiteralPath (Join-Path $script:ext 'bin\clang.cmd') -Destination (Join-Path $script:ext 'bin\clang++.cmd')
        }

        It 'fails fast on an unknown command and links an external toolchain' -Skip:($env:OS -ne 'Windows_NT') {
            $env:LLVM_HOME = $script:lhome
            $env:LLVM_TOOLCHAINS_DIR = Join-Path $script:lhome 'toolchains'
            $out = (& $script:launcher definitely-not-a-command 2>&1 | Out-String)
            $LASTEXITCODE | Should -Be 1
            $out | Should -Match 'Unknown command'
            & $script:launcher toolchain link ext $script:ext *> $null
            $LASTEXITCODE | Should -Be 0
            $envOut = (& $script:launcher env ext --format cmd | Out-String)
            $envOut | Should -Match 'set "CC=.*clang\.cmd"'
            $envOut | Should -Match 'set "AR="'
        }

        It 'streams child output live and returns the child exit code' -Skip:($env:OS -ne 'Windows_NT') {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
            $psi.Arguments = "/d /c `"`"$($script:launcher)`" +ext -- clang `"a b`"`""
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.EnvironmentVariables['LLVM_HOME'] = $script:lhome
            $psi.EnvironmentVariables['LLVM_TOOLCHAINS_DIR'] = (Join-Path $script:lhome 'toolchains')
            $p = [System.Diagnostics.Process]::Start($psi)
            $stamps = @{}
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $lines = @()
            while ($null -ne ($line = $p.StandardOutput.ReadLine())) {
                $lines += $line
                if ($line -match '^(first|second)') { $stamps[$matches[1]] = $sw.Elapsed.TotalSeconds }
            }
            $p.WaitForExit()
            $p.ExitCode | Should -Be 7
            ($lines -join "`n") | Should -Match 'arg=\[a b\]'
            ($stamps['second'] - $stamps['first']) | Should -BeGreaterThan 1.0
        }

        It 'keeps a single argument intact (help, list) and exits 0' -Skip:($env:OS -ne 'Windows_NT') {
            $env:LLVM_HOME = $script:lhome
            $env:LLVM_TOOLCHAINS_DIR = Join-Path $script:lhome 'toolchains'
            $help = & $script:launcher help 2>&1 | ForEach-Object { "$_" }
            $LASTEXITCODE | Should -Be 0
            ($help -join "`n") | Should -Match 'Usage: llvmup'
            $null = & $script:launcher list 2>&1
            $LASTEXITCODE | Should -Be 0
        }
    }
}
