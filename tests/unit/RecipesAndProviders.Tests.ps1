$ErrorActionPreference = 'Stop'

Describe 'LLVMUP Recipes, Multi-Provider Engine, and Ergonomic CLI' {
    BeforeAll {
        $script:isWin = $env:OS -eq 'Windows_NT'
        $script:otherSelector = if ($script:isWin) { 'winlibs@23.1.3' } else { 'official@23.1.6' }
        $script:otherProvider = ($script:otherSelector -split '@')[0]
        $script:hostKey = if ($script:isWin) { 'windows-x64' } else { 'linux-x64' }
        $script:otherPlatform = if ($script:isWin) { 'linux' } else { 'windows' }
        $script:compilerSuffix = if ($script:isWin) { '.exe' } else { '' }
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $pwshDir = Join-Path (Join-Path $repoRoot 'libexec') 'pwsh'
        Import-Module (Join-Path $repoRoot 'Llvm-Functions.psm1') -Force -Global -DisableNameChecking
        Import-Module (Join-Path $pwshDir 'Llvm-Recipes.psm1') -Force -Global -DisableNameChecking
        Import-Module (Join-Path $pwshDir 'Llvm-Manifest.psm1') -Force -Global -DisableNameChecking
        Import-Module (Join-Path $pwshDir 'Llvm-Downloader.psm1') -Force -Global -DisableNameChecking
        Import-Module (Join-Path $pwshDir 'Llvm-Verifier.psm1') -Force -Global -DisableNameChecking
        Import-Module (Join-Path $pwshDir 'Llvm-Extractor.psm1') -Force -Global -DisableNameChecking
        Import-Module (Join-Path $pwshDir 'Llvm-Resolver.psm1') -Force -Global -DisableNameChecking
        Import-Module (Join-Path $pwshDir 'Llvm-Environment.psm1') -Force -Global -DisableNameChecking
        Import-Module (Join-Path $pwshDir 'Llvm-Runner.psm1') -Force -Global -DisableNameChecking
        Import-Module (Join-Path $pwshDir 'Llvm-ConfigEngine.psm1') -Force -Global -DisableNameChecking
        Import-Module (Join-Path $pwshDir 'Llvm-CMake.psm1') -Force -Global -DisableNameChecking
        Import-Module (Join-Path $pwshDir 'Llvm-Installer.psm1') -Force -Global -DisableNameChecking

        function New-TestZipFromTree {
            param(
                [Parameter(Mandatory)][string]$SourceDir,
                [Parameter(Mandatory)][string]$ZipPath
            )
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
            [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceDir, $ZipPath, [System.IO.Compression.CompressionLevel]::Fastest, $true)
        }

        function New-TestTarXzFromDir {
            param(
                [Parameter(Mandatory)][string]$ParentDir,
                [Parameter(Mandatory)][string]$DirName,
                [Parameter(Mandatory)][string]$TarXzPath
            )
            if (Test-Path -LiteralPath $TarXzPath) { Remove-Item -LiteralPath $TarXzPath -Force }
            $szPath = $null
            foreach ($cand in @('C:\Program Files\7-Zip\7z.exe', 'C:\Program Files (x86)\7-Zip\7z.exe')) {
                if (Test-Path -LiteralPath $cand -PathType Leaf) { $szPath = $cand; break }
            }
            if (-not $szPath) {
                $cmd = Get-Command '7z.exe','7z','7zz.exe','7zz' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($cmd) { $szPath = $cmd.Source }
            }
            if ($szPath) {
                $tmpTar = "$TarXzPath.tmp.tar"
                if (Test-Path -LiteralPath $tmpTar) { Remove-Item -LiteralPath $tmpTar -Force }
                Push-Location $ParentDir
                try {
                    & $szPath a -y -ttar $tmpTar $DirName *> $null
                    if ($LASTEXITCODE -ne 0) { throw "7z tar creation failed with $LASTEXITCODE" }
                    & $szPath a -y -txz $TarXzPath $tmpTar *> $null
                    if ($LASTEXITCODE -ne 0) { throw "7z xz compression failed with $LASTEXITCODE" }
                } finally {
                    Pop-Location
                    Remove-Item -LiteralPath $tmpTar -Force -ErrorAction SilentlyContinue
                }
                return
            }
            Push-Location $ParentDir
            try {
                & tar -cJf $TarXzPath $DirName
                if ($LASTEXITCODE -ne 0) { throw "tar -cJf failed with $LASTEXITCODE" }
            } finally {
                Pop-Location
            }
        }

        function Get-TestFileUri([string]$Path) {
            [Uri]::new([IO.Path]::GetFullPath($Path), [UriKind]::Absolute).AbsoluteUri
        }

        function New-TestFixtureExecutable {
            param(
                [Parameter(Mandatory)][string]$Path,
                [string]$StubExePath = '',
                [string]$Body = 'echo clang version 23.1.6'
            )
            if (-not $script:isWin) { $Path = $Path -replace '\.exe$', '' }
            $dir = Split-Path $Path -Parent
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            if ($Path.EndsWith('.exe') -and $StubExePath -and (Test-Path -LiteralPath $StubExePath)) {
                Copy-Item -LiteralPath $StubExePath -Destination $Path -Force
            } else {
                Set-Content -LiteralPath $Path -Value "#!/bin/sh`n$Body`n" -Encoding Ascii
                if (-not $script:isWin) {
                    & chmod +x $Path
                    if ($LASTEXITCODE -ne 0) { throw "chmod failed for $Path" }
                }
            }
        }

        $script:savedEnv = @{}
        foreach ($varName in @(
            'LLVM_HOME', 'LLVM_TOOLCHAINS_DIR', 'LLVM_SOURCES_DIR', 'LLVMUP_CACHE_DIR',
            'LLVMUP_OFFICIAL_RELEASES_FILE', 'LLVMUP_WINLIBS_RELEASES_FILE', 'LLVMUP_LLVM_MINGW_RELEASES_FILE',
            'LLVMUP_ALLOW_UNVERIFIED', 'LLVMUP_ALLOW_FILE_URLS', 'LLVMUP_PREVIOUS_TOOLCHAIN', 'LLVMUP_SESSION_OVERRIDE',
            'PATH', 'LLVMUP_ACTIVE_PROVIDER', 'LLVMUP_ACTIVE_TOOLCHAIN', 'LLVMUP_ACTIVE_TARGET', 'LLVMUP_ACTIVE_COMPILER',
            'LLVMUP_ACTIVE_VERSION', 'LLVMUP_ACTIVE_PATH', 'LLVMUP_ACTIVE_ID', 'LLVMUP_PREVIOUS_SESSION',
            '_ACTIVE_LLVM', '_ACTIVE_LLVM_PATH', '_LLVM_BACKUP', '_LLVM_ORIGINAL_PATH', '_LLVM_ENV_BACKUP', 'CC', 'CXX', 'AR', 'RANLIB', 'RC',
            'CMAKE_C_COMPILER', 'CMAKE_CXX_COMPILER', 'LLVM_DIR', 'CMAKE_PREFIX_PATH', 'PKG_CONFIG_PATH'
        )) {
            $script:savedEnv[$varName] = [Environment]::GetEnvironmentVariable($varName, 'Process')
        }

        # Build one tiny real Win32 console stub executable once so --version checks pass in PS 5.1 & PS 7
        $script:stubExe = Join-Path $TestDrive 'stub-tool.exe'
        $cscPath = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
        if (Test-Path -LiteralPath $cscPath) {
            $csPath = Join-Path $TestDrive 'stub-tool.cs'
            Set-Content -LiteralPath $csPath -Value 'using System; public class Stub { public static int Main(string[] args) { Console.WriteLine("clang version 23.1.6"); return 0; } }' -Encoding Ascii
            & $cscPath /nologo /optimize+ /out:$script:stubExe $csPath *> $null
            if ($LASTEXITCODE -ne 0) { throw 'Failed to compile stub-tool.exe' }
        }
    }

    BeforeEach {
        $script:workRoot = Join-Path $TestDrive ("run-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:llvmHome = Join-Path $script:workRoot 'home'
        $script:toolchainsDir = Join-Path $script:llvmHome 'toolchains'
        $script:cacheDir = Join-Path $script:workRoot 'cache'
        $script:artifactsDir = Join-Path $script:workRoot ('artifacts # % ' + [char]0x00E9)
        $script:projectDir = Join-Path $script:workRoot 'project'
        foreach ($d in @($script:llvmHome, $script:toolchainsDir, $script:cacheDir, $script:artifactsDir, $script:projectDir)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }

        # Pin must find this project's file even if an ancestor has its own config.
        Set-Content -LiteralPath (Join-Path $script:projectDir '.llvmup-config') -Value '# Test project' -Encoding Ascii
        $env:LLVM_HOME = $script:llvmHome
        $env:LLVM_TOOLCHAINS_DIR = $script:toolchainsDir
        $env:LLVMUP_CACHE_DIR = $script:cacheDir
        $env:LLVMUP_ALLOW_FILE_URLS = '1'
        foreach ($v in @('LLVMUP_ACTIVE_TOOLCHAIN', '_ACTIVE_LLVM', 'LLVMUP_SESSION_OVERRIDE', 'LLVMUP_PREVIOUS_TOOLCHAIN',
                         'LLVMUP_ACTIVE_PROVIDER', 'LLVMUP_ACTIVE_TARGET', 'LLVMUP_ACTIVE_COMPILER',
                         'LLVMUP_ACTIVE_VERSION', 'LLVMUP_ACTIVE_PATH', 'LLVMUP_ACTIVE_ID', 'LLVMUP_PREVIOUS_SESSION',
                         '_ACTIVE_LLVM_PATH', '_LLVM_BACKUP', '_LLVM_ENV_BACKUP', '_LLVM_ORIGINAL_PATH', 'CC', 'CXX', 'AR', 'RANLIB', 'RC',
                         'CMAKE_C_COMPILER', 'CMAKE_CXX_COMPILER', 'LLVM_DIR', 'CMAKE_PREFIX_PATH', 'PKG_CONFIG_PATH')) {
            Remove-Item -LiteralPath "Env:$v" -ErrorAction SilentlyContinue
        }

        # 1) Official archive for the current host.
        $offParent = Join-Path $script:workRoot 'src-official'
        $offName = if ($script:isWin) { 'clang+llvm-23.1.6-x86_64-pc-windows-msvc' } else { 'LLVM-23.1.6-Linux-X64' }
        $offStage = Join-Path $offParent $offName
        New-TestFixtureExecutable -Path (Join-Path $offStage 'bin\clang.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $offStage 'bin\clang++.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $offStage 'bin\lld-link.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $offStage 'bin\llvm-config.exe') -StubExePath $script:stubExe
        New-Item -ItemType Directory -Path (Join-Path $offStage 'lib\cmake\llvm') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $offStage 'lib\cmake\llvm\LLVMConfig.cmake') -Value '# cmake' -Encoding Ascii
        $script:offArc = Join-Path $script:artifactsDir "$offName.tar.xz"
        New-TestTarXzFromDir -ParentDir $offParent -DirName $offName -TarXzPath $script:offArc
        $script:offSha = (Get-FileHash -LiteralPath $script:offArc -Algorithm SHA256).Hash.ToLowerInvariant()
        $offShaFile = "$($script:offArc).sha256"
        Set-Content -LiteralPath $offShaFile -Value "$($script:offSha)  $offName.tar.xz" -Encoding Ascii

        # 2) WinLibs archive (mingw64 wrapper dir with clang + gcc)
        $wlStage = Join-Path $script:workRoot 'src-winlibs\mingw64'
        New-TestFixtureExecutable -Path (Join-Path $wlStage 'bin\clang.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $wlStage 'bin\clang++.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $wlStage 'bin\gcc.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $wlStage 'bin\g++.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $wlStage 'bin\windres.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $wlStage 'bin\mingw32-make.exe') -StubExePath $script:stubExe
        $script:wlZip = Join-Path $script:artifactsDir 'winlibs-x86_64-posix-seh-gcc-16.2.0-llvm-23.1.3-mingw-w64ucrt-14.0.0-r3.zip'
        New-TestZipFromTree -SourceDir $wlStage -ZipPath $script:wlZip
        $script:wlSha = (Get-FileHash -LiteralPath $script:wlZip -Algorithm SHA256).Hash.ToLowerInvariant()
        $wlShaFile = "$($script:wlZip).sha256"
        Set-Content -LiteralPath $wlShaFile -Value "$($script:wlSha) *winlibs-x86_64-posix-seh-gcc-16.2.0-llvm-23.1.3-mingw-w64ucrt-14.0.0-r3.zip" -Encoding Ascii

        # 3) LLVM-MinGW archive with multi-target wrappers.
        $lmParent = Join-Path $script:workRoot 'src-llmmw'
        $lmStage = Join-Path $lmParent 'llvm-mingw-20261117-ucrt-x86_64'
        New-TestFixtureExecutable -Path (Join-Path $lmStage 'bin\clang.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $lmStage 'bin\clang++.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $lmStage 'bin\x86_64-w64-mingw32-clang.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $lmStage 'bin\x86_64-w64-mingw32-clang++.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $lmStage 'bin\aarch64-w64-mingw32-clang.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $lmStage 'bin\aarch64-w64-mingw32-clang++.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $lmStage 'bin\llvm-windres.exe') -StubExePath $script:stubExe
        New-TestFixtureExecutable -Path (Join-Path $lmStage 'bin\llvm-ar.exe') -StubExePath $script:stubExe
        $script:lmName = if ($script:isWin) { 'llvm-mingw-20261117-ucrt-x86_64.zip' } else { 'llvm-mingw-20261117-ucrt-ubuntu-22.04-x86_64.tar.xz' }
        $script:lmArchive = Join-Path $script:artifactsDir $script:lmName
        if ($script:isWin) {
            New-TestZipFromTree -SourceDir $lmStage -ZipPath $script:lmArchive
        } else {
            New-TestTarXzFromDir -ParentDir $lmParent -DirName (Split-Path $lmStage -Leaf) -TarXzPath $script:lmArchive
        }
        $script:lmSha = (Get-FileHash -LiteralPath $script:lmArchive -Algorithm SHA256).Hash.ToLowerInvariant()

        # Offline release fixture JSON files
        $offUri = (Get-TestFileUri $script:offArc)
        $offShaUri = (Get-TestFileUri $offShaFile)
        $officialReleases = @(
            @{
                tag_name = 'llvmorg-23.1.6'
                prerelease = $false
                assets = @(
                    @{ name = "$offName.tar.xz"; browser_download_url = $offUri; digest = "sha256:$($script:offSha)"; size = 1024 }
                    @{ name = "$offName.tar.xz.sha256"; browser_download_url = $offShaUri; size = 80 }
                )
            }
        )
        $env:LLVMUP_OFFICIAL_RELEASES_FILE = Join-Path $script:artifactsDir 'official-releases.json'
        Set-Content -LiteralPath $env:LLVMUP_OFFICIAL_RELEASES_FILE -Value (ConvertTo-Json -InputObject $officialReleases -Depth 6) -Encoding UTF8

        $wlUri = (Get-TestFileUri $script:wlZip)
        $wlShaUri = (Get-TestFileUri $wlShaFile)
        $winlibsReleases = @(
            # Newer release WITHOUT LLVM (GCC-only) -- must NOT match default llvm-required winlibs
            @{
                tag_name = '16.2.0posix-14.0.0-ucrt-r9'
                prerelease = $false
                assets = @(
                    @{ name = 'winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r9.zip'; browser_download_url = 'https://example.invalid/gcc-only.zip'; size = 1024 }
                )
            },
            # Release WITH LLVM 23.1.3
            @{
                tag_name = '16.2.0posix-23.1.3-14.0.0-ucrt-r3'
                prerelease = $false
                assets = @(
                    @{ name = 'winlibs-x86_64-posix-seh-gcc-16.2.0-llvm-23.1.3-mingw-w64ucrt-14.0.0-r3.zip'; browser_download_url = $wlUri; size = 1024 }
                    @{ name = 'winlibs-x86_64-posix-seh-gcc-16.2.0-llvm-23.1.3-mingw-w64ucrt-14.0.0-r3.zip.sha256'; browser_download_url = $wlShaUri; size = 80 }
                )
            }
        )
        $env:LLVMUP_WINLIBS_RELEASES_FILE = Join-Path $script:artifactsDir 'winlibs-releases.json'
        Set-Content -LiteralPath $env:LLVMUP_WINLIBS_RELEASES_FILE -Value (ConvertTo-Json -InputObject $winlibsReleases -Depth 6) -Encoding UTF8

        $lmUri = (Get-TestFileUri $script:lmArchive)
        $lmReleases = @(
            @{
                tag_name = '20261117'
                name = 'llvm-mingw 20261117 with LLVM 23.1.6'
                body = 'Includes LLVM 23.1.6 toolchains'
                prerelease = $false
                assets = @(
                    @{ name = $script:lmName; browser_download_url = $lmUri; digest = "sha256:$($script:lmSha)"; size = 1024 }
                    if ($script:isWin) {
                        @{ name = 'llvm-mingw-20261117-ucrt-ubuntu-22.04-x86_64.tar.xz'; browser_download_url = 'https://example.invalid/lm-linux.tar.xz'; digest = "sha256:$('0' * 64)"; size = 1024 }
                    } else {
                        @{ name = 'llvm-mingw-20261117-ucrt-x86_64.zip'; browser_download_url = 'https://example.invalid/lm-windows.zip'; digest = "sha256:$('0' * 64)"; size = 1024 }
                    }
                )
            }
        )
        $env:LLVMUP_LLVM_MINGW_RELEASES_FILE = Join-Path $script:artifactsDir 'llmmw-releases.json'
        Set-Content -LiteralPath $env:LLVMUP_LLVM_MINGW_RELEASES_FILE -Value (ConvertTo-Json -InputObject $lmReleases -Depth 6) -Encoding UTF8
    }

    AfterEach {
        foreach ($v in @('LLVMUP_OFFICIAL_RELEASES_FILE', 'LLVMUP_WINLIBS_RELEASES_FILE', 'LLVMUP_LLVM_MINGW_RELEASES_FILE', 'LLVMUP_ALLOW_FILE_URLS')) {
            Remove-Item -LiteralPath "Env:$v" -ErrorAction SilentlyContinue
        }
        if ($env:_LLVM_BACKUP) { Deactivate-Llvm | Out-Null }
    }

    AfterAll {
        foreach ($kv in $script:savedEnv.GetEnumerator()) {
            if ($null -eq $kv.Value) {
                Remove-Item -LiteralPath "Env:$($kv.Key)" -ErrorAction SilentlyContinue
            } else {
                [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, 'Process')
            }
        }
    }

    Context 'Recipes and Multi-Provider Resolution' {
        It 'lists all built-in providers and parses provider@version selectors' {
            $providers = Get-LlvmProviderList
            $providers.Count | Should -BeGreaterOrEqual 3
            ($providers | ForEach-Object { $_.provider }) | Should -Contain 'official'
            ($providers | ForEach-Object { $_.provider }) | Should -Contain 'winlibs'
            ($providers | ForEach-Object { $_.provider }) | Should -Contain 'llvm-mingw'

            $s1 = Split-LlvmSelector -Selector 'winlibs@23'
            $s1.provider | Should -Be 'winlibs'
            $s1.expression | Should -Be '23'

            $s2 = Split-LlvmSelector -Selector 'llvm-mingw@20261117'
            $s2.provider | Should -Be 'llvm-mingw'
            $s2.expression | Should -Be '20261117'
        }

        It 'skips GCC-only WinLibs releases and orders r10 above r9' {
            $wlReleases = @((Get-Content -LiteralPath $env:LLVMUP_WINLIBS_RELEASES_FILE -Raw | ConvertFrom-Json) | ForEach-Object { $_ })
            $plan = Resolve-LlvmRecipeInstallPlan -Provider 'winlibs' -Releases $wlReleases -VersionExpression 'latest' -Platform 'windows' -Arch 'x64' -Crt 'ucrt'
            $plan.release_tag | Should -Be '16.2.0posix-23.1.3-14.0.0-ucrt-r3'
            $plan.llvm_version | Should -Be '23.1.3'
            $plan.asset.name | Should -Be 'winlibs-x86_64-posix-seh-gcc-16.2.0-llvm-23.1.3-mingw-w64ucrt-14.0.0-r3.zip'

            $r9r10 = @(
                @{ tag_name = '16.2.0posix-23.1.3-14.0.0-ucrt-r9'; prerelease = $false; assets = @(@{ name = 'winlibs-x86_64-posix-seh-gcc-16.2.0-llvm-23.1.3-mingw-w64ucrt-14.0.0-r9.zip'; browser_download_url = 'https://example.invalid/r9.zip'; size = 1 }) },
                @{ tag_name = '16.2.0posix-23.1.3-14.0.0-ucrt-r10'; prerelease = $false; assets = @(@{ name = 'winlibs-x86_64-posix-seh-gcc-16.2.0-llvm-23.1.3-mingw-w64ucrt-14.0.0-r10.zip'; browser_download_url = 'https://example.invalid/r10.zip'; size = 1 }) }
            )
            $p10 = Resolve-LlvmRecipeInstallPlan -Provider 'winlibs' -Releases $r9r10 -VersionExpression 'latest' -Platform 'windows' -Arch 'x64'
            $p10.release_tag | Should -Be '16.2.0posix-23.1.3-14.0.0-ucrt-r10'
        }

        It 'extracts LLVM version from llvm-mingw metadata and resolves Linux->Windows cross-compile asset' {
            $releases = @((Get-Content -LiteralPath $env:LLVMUP_LLVM_MINGW_RELEASES_FILE -Raw | ConvertFrom-Json) | ForEach-Object { $_ })
            $winPlan = Resolve-LlvmRecipeInstallPlan -Provider 'llvm-mingw' -Releases $releases -VersionExpression '23' -Platform 'windows' -Arch 'x64' -Crt 'ucrt'
            $winPlan.release_tag | Should -Be '20261117'
            $winPlan.llvm_version | Should -Be '23.1.6'
            $winPlan.asset.name | Should -Be 'llvm-mingw-20261117-ucrt-x86_64.zip'

            $linuxPlan = Resolve-LlvmRecipeInstallPlan -Provider 'llvm-mingw' -Releases $releases -VersionExpression 'latest' -Platform 'linux' -Arch 'x64' -Crt 'ucrt'
            $linuxPlan.asset.name | Should -Be 'llvm-mingw-20261117-ucrt-ubuntu-22.04-x86_64.tar.xz'
            $linuxPlan.default_target | Should -Be 'x86_64-w64-mingw32'
        }
    }

    Context 'Verification, Extraction Safety, Cache, and Multi-Provider Installation' {
        It 'rejects checksum mismatches, unpermitted file:// URLs, strict unverified assets, and path traversal archive entries' {
            $badFile = Join-Path $script:workRoot 'bad.zip'
            Copy-Item -LiteralPath $script:wlZip -Destination $badFile
            Add-Content -LiteralPath $badFile -Value 'corrupt'
            $planWithSha = [ordered]@{
                provider = 'winlibs'
                recipe = (Get-LlvmRecipe -Provider 'winlibs')
                asset = [ordered]@{ name = 'winlibs.zip'; digest = "sha256:$($script:wlSha)" }
                verification_assets = [ordered]@{ sha256 = $null; sha512 = $null; sig = $null; jsonl = $null }
            }
            { Invoke-LlvmAssetVerify -ArtifactPath $badFile -Plan $planWithSha -TempPath $script:workRoot -Policy 'strict' } | Should -Throw

            $planNoMeta = [ordered]@{
                provider = 'winlibs'
                recipe = (Get-LlvmRecipe -Provider 'winlibs')
                asset = [ordered]@{ name = 'winlibs.zip'; digest = '' }
                verification_assets = [ordered]@{ sha256 = $null; sha512 = $null; sig = $null; jsonl = $null }
            }
            { Invoke-LlvmAssetVerify -ArtifactPath $script:wlZip -Plan $planNoMeta -TempPath $script:workRoot -Policy 'strict' } | Should -Throw

            # Path traversal entry test
            Test-LlvmSafeArchiveEntryName -EntryName 'dir/bin/clang.exe' | Should -BeTrue
            Test-LlvmSafeArchiveEntryName -EntryName '../evil.exe' | Should -BeFalse
            Test-LlvmSafeArchiveEntryName -EntryName 'C:\Windows\System32\evil.exe' | Should -BeFalse

            # Disallow file:// URLs unless explicitly opted in
            Remove-Item -LiteralPath 'Env:LLVMUP_ALLOW_FILE_URLS' -ErrorAction SilentlyContinue
            { Invoke-LlvmDownloadFile -Url (Get-TestFileUri $script:wlZip) -DestinationPath (Join-Path $script:workRoot 'blocked.zip') } | Should -Throw '*unsupported download scheme*'
        }

        It 'installs the host providers, caches archives, and writes toolchain manifests' {
            llvmup install official@23.1.6 --quiet | Should -BeTrue
            if ($script:isWin) { llvmup install winlibs@23.1.3 --crt ucrt --quiet | Should -BeTrue }
            llvmup install llvm-mingw@20261117 --crt ucrt --quiet | Should -BeTrue

            # Each provider can reuse its downloaded archive.
            $cachedArchives = @(Get-ChildItem -LiteralPath $script:cacheDir -Recurse -File)
            $count = if ($script:isWin) { 3 } else { 2 }
            $cachedArchives.Count | Should -BeGreaterOrEqual $count

            $all = Get-LlvmAllToolchains -ToolchainsPath $script:toolchainsDir -HomePath $script:llvmHome
            $all.Count | Should -Be $count

            $lmManifest = $all | Where-Object { $_.provider -eq 'llvm-mingw' }
            $lmManifest.llvm_version | Should -Be '23.1.6'
            $lmManifest.provider_release | Should -Be '20261117'
            $lmManifest.supported_targets | Should -Contain 'x86_64-w64-mingw32'
            $lmManifest.supported_targets | Should -Contain 'aarch64-w64-mingw32'
            Test-Path -LiteralPath (Join-Path $lmManifest.root_path '.llvmup-toolchain.json') | Should -BeTrue

            # Strip the top-level wrapper so bin sits directly under the install root.
            Test-Path -LiteralPath (Join-Path $lmManifest.root_path "bin/clang$script:compilerSuffix") | Should -BeTrue
        }
    }

    Context 'Environment Switching, use/run/+toolchain, aliases, pin/sync, external link, and CMake' {
        BeforeEach {
            llvmup install official@23.1.6 --quiet | Should -BeTrue
            if ($script:isWin) { llvmup install winlibs@23.1.3 --crt ucrt --quiet | Should -BeTrue }
            llvmup install llvm-mingw@20261117 --crt ucrt --quiet | Should -BeTrue
        }

        It 'switches between installed providers, restores the previous toolchain, and deactivates' {
            llvmup use official@23.1.6 | Should -BeTrue
            $env:LLVMUP_ACTIVE_PROVIDER | Should -Be 'official'
            $env:CC | Should -Match '[\\/]clang(?:\.exe)?$'

            if ($script:isWin) {
                llvmup use winlibs@23.1.3 --compiler gcc | Should -BeTrue
                $env:LLVMUP_ACTIVE_PROVIDER | Should -Be 'winlibs'
                $env:LLVMUP_ACTIVE_COMPILER | Should -Be 'gcc'
                $env:CC | Should -Match '[\\/]gcc\.exe$'
                $env:CXX | Should -Match '[\\/]g\+\+\.exe$'
                $env:RC | Should -Match '[\\/]windres\.exe$'
            }

            llvmup use llvm-mingw@20261117 --target aarch64-w64-mingw32 | Should -BeTrue
            $env:LLVMUP_ACTIVE_PROVIDER | Should -Be 'llvm-mingw'
            $env:LLVMUP_ACTIVE_TARGET | Should -Be 'aarch64-w64-mingw32'
            $env:CC | Should -Match '[\\/]aarch64-w64-mingw32-clang(?:\.exe)?$'
            $env:LLVMUP_PREVIOUS_SESSION | Should -Match $(if ($script:isWin) { 'winlibs' } else { 'llvmorg' })

            # Swap back to previous toolchain
            llvmup use - | Should -BeTrue
            $env:LLVMUP_ACTIVE_PROVIDER | Should -Be $script:otherProvider

            llvmup deactivate | Should -BeTrue
            $env:LLVMUP_ACTIVE_TOOLCHAIN | Should -BeNullOrEmpty
            $env:CC | Should -BeNullOrEmpty
            $env:LLVMUP_PREVIOUS_SESSION | Should -BeNullOrEmpty
        }

        It 'executes +toolchain and run in isolated process env with exit code preservation' {
            llvmup use official@23.1.6 | Should -BeTrue

            $probe = Join-Path $script:workRoot 'child.ps1'
            Set-Content -LiteralPath $probe -Value 'Write-Output "ACTIVE=$env:LLVMUP_ACTIVE_PROVIDER"; exit 7' -Encoding Ascii
            $engine = (Get-Process -Id $PID).Path
            $out = llvmup +llvm-mingw@20261117 -- $engine -NoProfile -File $probe
            $LASTEXITCODE | Should -Be 7
            ($out -join "`n") | Should -Match 'ACTIVE=llvm-mingw'
            $env:LLVMUP_ACTIVE_PROVIDER | Should -Be 'official'
            (Split-Path $env:CC -Leaf) | Should -Be "clang$script:compilerSuffix"

            $out = llvmup run llvm-mingw@20261117 -- $engine -NoProfile -File $probe
            $LASTEXITCODE | Should -Be 7
            ($out -join "`n") | Should -Match 'ACTIVE=llvm-mingw'
            $env:LLVMUP_ACTIVE_PROVIDER | Should -Be 'official'
            (Split-Path $env:CC -Leaf) | Should -Be "clang$script:compilerSuffix"
        }

        It 'manages aliases, pins, lockfiles, sync --locked, external toolchain link/unlink, inspection commands, and cmake-toolchain' {
            llvmup alias set test-alias $script:otherSelector | Should -BeTrue
            (llvmup alias show test-alias) | Should -Match $script:otherProvider
            llvmup use test-alias | Should -BeTrue
            $env:LLVMUP_ACTIVE_PROVIDER | Should -Be $script:otherProvider

            # External toolchain link / unlink
            $extDir = Join-Path $script:workRoot 'external-llvm'
            New-TestFixtureExecutable -Path (Join-Path $extDir 'bin\clang.exe') -StubExePath $script:stubExe
            New-TestFixtureExecutable -Path (Join-Path $extDir 'bin\clang++.exe') -StubExePath $script:stubExe
            llvmup toolchain link custom-ext $extDir | Should -BeTrue
            (Get-LlvmAllToolchains -ToolchainsPath $script:toolchainsDir -HomePath $script:llvmHome | ForEach-Object { $_.install_name }) | Should -Contain 'custom-ext'
            llvmup toolchain unlink custom-ext | Should -BeTrue

            # Inspection commands & status --explain --json
            (llvmup which clang) | Should -Match 'clang(?:\.exe)?$'
            (llvmup where test-alias) | Should -Match $(if ($script:isWin) { 'winlibs' } else { 'llvmorg' })
            if ($script:isWin) { (llvmup provides windres) | Should -Match 'winlibs' }
            $statusJson = llvmup status --explain --json | ConvertFrom-Json
            $statusJson.active_version | Should -Not -BeNullOrEmpty
            $statusJson.selected_for_execution.reason | Should -Not -BeNullOrEmpty

            # CMake toolchain file generation
            $cmakeOut = Join-Path $script:projectDir 'arm64-mingw.cmake'
            $generated = llvmup cmake-toolchain llvm-mingw@20261117 --target aarch64-w64-mingw32 --output $cmakeOut
            Test-Path -LiteralPath $generated | Should -BeTrue
            $cmakeText = Get-Content -LiteralPath $generated -Raw
            $cmakeText | Should -Match 'CMAKE_SYSTEM_NAME Windows'
            $cmakeText | Should -Match ([regex]::Escape("aarch64-w64-mingw32-clang$script:compilerSuffix"))

            # Project pin, lock, and sync --locked
            $parentConfig = Join-Path $script:workRoot '.llvmup-config'
            $parentProfile = "[profile]`ntype = `"minimal`"`n"
            [IO.File]::WriteAllText($parentConfig, $parentProfile)
            Push-Location $script:projectDir
            try {
                llvmup pin llvm-mingw@20261117 --crt ucrt --target x86_64-w64-mingw32 | Should -BeTrue
                (Read-LlvmProjectConfigData -ConfigPath '.llvmup-config').provider | Should -Be 'llvm-mingw'
                [IO.File]::ReadAllText($parentConfig) | Should -Be $parentProfile
                llvmup config lock | Should -BeTrue
                Test-Path -LiteralPath (Join-Path $script:projectDir '.llvmup-lock.json') | Should -BeTrue

                # Remove installed llvm-mingw and restore purely via sync --locked
                $lockedEntry = (Get-Content -LiteralPath '.llvmup-lock.json' -Raw | ConvertFrom-Json).entries.($script:hostKey)
                llvmup alias set $lockedEntry.canonical_id $script:otherSelector | Should -BeTrue
                $lmDir = (Get-LlvmAllToolchains -ToolchainsPath $script:toolchainsDir -HomePath $script:llvmHome | Where-Object { $_.provider -eq 'llvm-mingw' }).root_path
                Remove-Item -LiteralPath $lmDir -Recurse -Force
                llvmup sync --locked | Should -BeTrue
                llvmup sync --locked | Should -BeTrue
                $restored = Resolve-LlvmInstalledToolchain -Selector 'llvm-mingw@20261117' -ToolchainsPath $script:toolchainsDir -HomePath $script:llvmHome
                $restored | Should -Not -BeNullOrEmpty
            } finally {
                Pop-Location
            }
        }

        It 'rejects an alias when its install name now belongs to a different toolchain' {
            llvmup alias set reused-name llvm-mingw@20261117 | Should -BeTrue
            $original = Resolve-LlvmInstalledToolchain -Selector 'reused-name'
            $manifestPath = Join-Path $original.root_path '.llvmup-toolchain.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifest.id = 'different'
            $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
            { Resolve-LlvmInstalledToolchain -Selector 'reused-name' } | Should -Throw '*no longer matches an installed toolchain*'
        }

        It 'rejects a restored provider installation whose manifest compiler is missing' {
            $manifest = Resolve-LlvmInstalledToolchain -Selector 'llvm-mingw@20261117'
            Remove-Item -LiteralPath (Join-Path $manifest.root_path $manifest.tools.clang)
            $result = @(llvmup install llvm-mingw@20261117 --quiet 2>&1)
            $result | Should -Contain $false
            ($result | Out-String) | Should -Match 'compiler.*unavailable'
        }

        It 'covers list --providers/--remote, resolve --config, config lock per host, run --locked, default shorthand, update and use --auto' {
            $prov = (llvmup list --providers) | Out-String
            $prov | Should -Match 'winlibs'
            $prov | Should -Match 'llvm-mingw'
            ((llvmup list --remote --provider llvm-mingw) | Out-String) | Should -Match '20261117'

            Push-Location $script:projectDir
            try {
                llvmup pin llvm-mingw@20261117 --crt ucrt --target x86_64-w64-mingw32 | Should -BeTrue
                ((llvmup resolve --config) | Out-String) | Should -Match '20261117'

                llvmup config lock | Should -BeTrue
                llvmup config lock --platform $script:otherPlatform --arch x64 | Should -BeTrue
                $lock = Get-Content -LiteralPath (Join-Path $script:projectDir '.llvmup-lock.json') -Raw | ConvertFrom-Json
                @($lock.entries.PSObject.Properties.Name | Sort-Object) | Should -Be @('linux-x64', 'windows-x64')
                $lock.entries.'linux-x64'.asset.name | Should -Be 'llvm-mingw-20261117-ucrt-ubuntu-22.04-x86_64.tar.xz'

                $probe = Join-Path $script:workRoot 'locked.ps1'
                Set-Content -LiteralPath $probe -Value 'Write-Output $env:LLVMUP_ACTIVE_PROVIDER; exit 4' -Encoding Ascii
                $engine = (Get-Process -Id $PID).Path
                $out = llvmup run --locked -- $engine -NoProfile -File $probe
                $LASTEXITCODE | Should -Be 4
                ($out -join "`n") | Should -Match 'llvm-mingw'

                $lockPath = Join-Path $script:projectDir '.llvmup-lock.json'
                $originalLock = Get-Content -LiteralPath $lockPath -Raw
                try {
                    $lock.entries.($script:hostKey).asset.name = 'different.zip'
                    $lock | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $lockPath -Encoding UTF8
                    llvmup sync --locked 2>$null | Should -BeFalse
                    llvmup run --locked -- $engine -NoProfile -File $probe 2>$null | Should -BeFalse
                } finally {
                    [IO.File]::WriteAllText($lockPath, $originalLock)
                }

                # Project config selects llvm-mingw; a manual 'use' overrides it until 'use --auto'.
                llvmup use $script:otherSelector | Should -BeTrue
                $env:LLVMUP_ACTIVE_PROVIDER | Should -Be $script:otherProvider
                llvmup use --auto | Should -BeTrue
                $env:LLVMUP_SESSION_OVERRIDE | Should -BeNullOrEmpty
                $env:LLVMUP_ACTIVE_PROVIDER | Should -Be 'llvm-mingw'
            } finally {
                Pop-Location
            }

            # A selected target maps known tools to the distribution's target wrappers.
            (llvmup which clang --toolchain llvm-mingw@20261117 --target aarch64-w64-mingw32) | Should -Match 'aarch64-w64-mingw32-clang(?:\.exe)?$'

            # pick: local list with aliases; fails without a terminal, selects with a choice.
            llvmup alias set pick-me llvm-mingw@20261117 | Should -BeTrue
            Mock Test-LlvmInteractiveConsole -ModuleName Llvm-Functions { $false }
            llvmup pick 2>$null | Should -BeFalse
            Mock Test-LlvmInteractiveConsole -ModuleName Llvm-Functions { $true }
            Mock Write-Host -ModuleName Llvm-Functions { $script:pickLines += "$Object" }
            $script:pickLines = @()
            $all = @(Get-LlvmAllToolchains -ToolchainsPath $script:toolchainsDir -HomePath $script:llvmHome | Where-Object { -not $_.missing_on_disk })
            $lmIndex = 1 + [array]::IndexOf(@($all | ForEach-Object { $_.provider }), 'llvm-mingw')
            Mock Read-Host -ModuleName Llvm-Functions { "$lmIndex" }
            llvmup pick | Should -BeTrue
            $env:LLVMUP_ACTIVE_PROVIDER | Should -Be 'llvm-mingw'
            ($script:pickLines -join "`n") | Should -Match 'aliases=pick-me'

            llvmup default $script:otherSelector | Should -BeTrue
            (llvmup default) | Should -Match $(if ($script:isWin) { 'winlibs' } else { 'llvmorg' })
            # Write-Host is mocked above, so the messages land in $script:pickLines.
            $script:pickLines = @()
            $null = llvmup update llvm-mingw@20261117
            ($script:pickLines -join "`n") | Should -Match 'up to date'
            llvmup update no-such-toolchain 2>$null | Should -BeFalse
        }

        It 'update installs a newer release beside the old one without touching aliases or the default; install --use activates; shell runs non-interactively' {
            llvmup alias set keep-me llvm-mingw@20261117 | Should -BeTrue
            llvmup default llvm-mingw@20261117 | Should -BeTrue
            $beforeDirs = @(Get-ChildItem -LiteralPath $script:toolchainsDir -Directory | ForEach-Object Name)

            $lmUri = (Get-TestFileUri $script:lmArchive)
            $newer = @(
                @{
                    tag_name = '20261201'; name = 'llvm-mingw 20261201 with LLVM 23.1.7'; body = 'Includes LLVM 23.1.7 toolchains'; prerelease = $false
                    assets = @(@{ name = ($script:lmName.Replace('20261117', '20261201')); browser_download_url = $lmUri; digest = "sha256:$($script:lmSha)"; size = 1024 })
                }
            )
            $all = @($newer) + @(Get-Content -LiteralPath $env:LLVMUP_LLVM_MINGW_RELEASES_FILE -Raw | ConvertFrom-Json | ForEach-Object { $_ })
            Set-Content -LiteralPath $env:LLVMUP_LLVM_MINGW_RELEASES_FILE -Value (ConvertTo-Json -InputObject $all -Depth 8) -Encoding UTF8

            $upd = (llvmup update llvm-mingw@20261117 *>&1 | Out-String)
            $upd | Should -Match 'installing'
            $afterDirs = @(Get-ChildItem -LiteralPath $script:toolchainsDir -Directory | ForEach-Object Name)
            @($beforeDirs | Where-Object { $_ -notin $afterDirs }) | Should -BeNullOrEmpty
            @($afterDirs | Where-Object { $_ -notin $beforeDirs }).Count | Should -BeGreaterThan 0
            ((llvmup default) | Out-String) | Should -Match '20261117'
            ((llvmup alias list) | Out-String) | Should -Match 'keep-me'
            ((llvmup update llvm-mingw@20261117 *>&1 | Out-String)) | Should -Match 'up to date'

            # install --use activates what was installed.
            Deactivate-Llvm
            $env:LLVMUP_ACTIVE_PROVIDER = $null
            llvmup install $script:otherSelector --quiet --use | Should -BeTrue
            $env:LLVMUP_ACTIVE_PROVIDER | Should -Be $script:otherProvider

            # shell with an explicit non-interactive program: environment applied, exit code surfaced, parent untouched.
            $probe = Join-Path $script:workRoot 'shell-probe.cmd'
            if ($script:isWin) {
                Set-Content -LiteralPath $probe -Value "@echo off`r`necho SHELLPROV=%LLVMUP_ACTIVE_PROVIDER%> `"$script:workRoot\shell-out.txt`"" -Encoding ASCII
            } else {
                $probe = Join-Path $script:workRoot 'shell-probe'
                New-TestFixtureExecutable -Path $probe -Body 'printf "SHELLPROV=%s\n" "$LLVMUP_ACTIVE_PROVIDER" > "$(dirname "$0")/shell-out.txt"'
            }
            $env:LLVMUP_ACTIVE_PROVIDER = 'parent-value'
            llvmup shell llvm-mingw@20261117 --shell $probe
            (Get-Content -LiteralPath (Join-Path $script:workRoot 'shell-out.txt') -Raw).Trim() | Should -Be 'SHELLPROV=llvm-mingw'
            $env:LLVMUP_ACTIVE_PROVIDER | Should -Be 'parent-value'
        }
    }
}
