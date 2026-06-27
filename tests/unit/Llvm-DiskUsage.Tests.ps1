Describe "LLVM Disk Usage" {
    BeforeAll {
        $ModulePath = Join-Path $PSScriptRoot "..\..\Llvm-Functions-Core.psm1"
        Import-Module $ModulePath -Force

        function New-TestFileWithSize {
            param(
                [Parameter(Mandatory = $true)][string]$Path,
                [Parameter(Mandatory = $true)][int]$Bytes
            )

            $parent = Split-Path $Path -Parent
            if ($parent) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }

            $content = [byte[]]::new($Bytes)
            [System.IO.File]::WriteAllBytes($Path, $content)
        }
    }

    BeforeEach {
        $script:TestToolchainsPath = Join-Path $TestDrive "toolchains"
        New-Item -ItemType Directory -Path $script:TestToolchainsPath -Force | Out-Null
    }

    AfterEach {
        $script:TOOLCHAINS_DIR = $null
    }

    It "Returns one entry per installation plus a total row" {
        New-TestFileWithSize -Path (Join-Path $script:TestToolchainsPath "llvmorg-19.1.7/bin/clang.exe") -Bytes 1536
        New-TestFileWithSize -Path (Join-Path $script:TestToolchainsPath "llvmorg-20.1.0/bin/clang.exe") -Bytes 2048

        $results = Get-LlvmDiskUsageData -ToolchainsPath $script:TestToolchainsPath

        $results.Count | Should -Be 3
        $results[0].Version | Should -Be "llvmorg-19.1.7"
        $results[0].Bytes | Should -Be 1536
        $results[1].Version | Should -Be "llvmorg-20.1.0"
        $results[1].Bytes | Should -Be 2048
        $results[2].Version | Should -Be "total"
        $results[2].Bytes | Should -Be 3584
        $results[2].Path | Should -Be $script:TestToolchainsPath
    }

    It "Adds a human-readable size when requested" {
        New-TestFileWithSize -Path (Join-Path $script:TestToolchainsPath "llvmorg-21.1.0/bin/clang.exe") -Bytes 2048

        $results = Get-LlvmDiskUsageData -ToolchainsPath $script:TestToolchainsPath -HumanReadable

        $results[0].Size | Should -Be "2.0 KiB"
        $results[-1].Size | Should -Be "2.0 KiB"
    }

    It "Respects the session toolchains path when no path parameter is provided" {
        New-TestFileWithSize -Path (Join-Path $script:TestToolchainsPath "llvmorg-22.0.0/bin/clang.exe") -Bytes 512
        $script:TOOLCHAINS_DIR = $script:TestToolchainsPath

        $results = Get-LlvmDiskUsageData

        $results[0].Version | Should -Be "llvmorg-22.0.0"
        $results[0].Bytes | Should -Be 512
    }

    It "Returns an empty collection for a missing toolchains directory" {
        $missing = Join-Path $TestDrive "missing-toolchains"

        $results = Get-LlvmDiskUsageData -ToolchainsPath $missing

        @($results).Count | Should -Be 0
    }
}
