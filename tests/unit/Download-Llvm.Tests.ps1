Describe 'Download-Llvm compatibility entrypoint' {
    BeforeAll {
        $script:download = Join-Path $PSScriptRoot '../../Download-Llvm.ps1'
        $script:fixture = (Resolve-Path (Join-Path $PSScriptRoot '../fixtures/releases/official.json')).Path
    }

    BeforeEach {
        $script:savedReleases = $env:LLVMUP_OFFICIAL_RELEASES_FILE
        $script:savedFormats = $env:LLVMUP_ASSET_FORMATS
        $env:LLVMUP_OFFICIAL_RELEASES_FILE = $script:fixture
        $env:LLVMUP_ASSET_FORMATS = 'tar.xz'
    }

    AfterEach {
        $env:LLVMUP_OFFICIAL_RELEASES_FILE = $script:savedReleases
        $env:LLVMUP_ASSET_FORMATS = $script:savedFormats
    }

    It 'lists stable official releases from the shared release reader' {
        $result = & $script:download -ListOnly -OutputFormat Json | ConvertFrom-Json
        $result.provider | Should -Be 'official'
        $result.remote_versions | Should -Contain 'llvmorg-23.1.6'
        @($result.remote_versions | Where-Object { $_ -match '-rc|beta' }).Count | Should -Be 0
    }

    It 'resolves the official Linux archive using the canonical installer' {
        $result = & $script:download -Version '~23.1' -Platform Linux -Arch x64 -ArchiveOnly -ResolveOnly -OutputFormat Json | ConvertFrom-Json
        $result.release | Should -Be 'llvmorg-23.1.6'
        $result.asset_name | Should -Match 'Linux-X64\.tar\.xz$'
        $result.asset_digest | Should -Match '^sha256:[0-9a-f]{64}$'
    }
}
