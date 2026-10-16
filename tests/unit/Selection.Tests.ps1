Describe 'Shared component selection' {
    BeforeAll {
        $repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        Import-Module (Join-Path $repo 'libexec/Llvm-Selection.psm1') -Force
    }

    It 'keeps full installations independent of Python' {
        InModuleScope Llvm-Selection {
            Mock Get-LlvmPython { throw 'Python should not be invoked' }
            $selection = Get-LlvmSelection
            $selection.enabled | Should -BeFalse
            $selection.key | Should -Be 'full'
        }
    }

    It 'normalizes equivalent compiler and custom selections' {
        $compiler = Get-LlvmSelection -Profile compiler
        $components = @('llvm-cov,llvm-profdata', 'lld', 'llvm-ar', 'llvm-ranlib')
        if (-not $IsWindows) { $components += 'libc++' }
        $custom = Get-LlvmSelection -Components $components
        $compiler.key | Should -Be $custom.key
        $compiler.components | Should -Contain clang
        $compiler.targets | Should -Contain 'clang-resource-headers'
    }

    It 'rejects incompatible installed profiles without modifying files' {
        $directory = Join-Path $TestDrive 'toolchain'
        New-Item -ItemType Directory -Path $directory | Out-Null
        '{"components":["clang"],"strip":false}' | Set-Content (Join-Path $directory '.llvmup-installation.json')
        { Invoke-LlvmSelection -Operation check -Root $directory -Selection (Get-LlvmSelection) } | Should -Throw '*differ*'
        Test-Path (Join-Path $directory '.llvmup-installation.json') | Should -BeTrue
    }

    It 'preserves legacy source project selections' {
        $selection = Get-LlvmSelection -Components @('clang', 'lldb') -Source
        $selection.legacy | Should -BeTrue
        $selection.selective | Should -BeFalse
        $selection.projects | Should -Contain lldb
    }
}
