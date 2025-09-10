Describe 'Auto-activation' {
    BeforeAll {
        Import-Module -Force (Join-Path $PSScriptRoot '../../Llvm-Functions-Core.psm1')
        $Script:testDir = Join-Path $PSScriptRoot 'ps-auto'
        New-Item -ItemType Directory -Path $Script:testDir -Force | Out-Null
        $env:USERPROFILE = $Script:testDir
        $global:toolchains = Join-Path $env:USERPROFILE '.llvm\toolchains'
        New-Item -ItemType Directory -Path $global:toolchains -Force | Out-Null
        # create a version and a .llvmup-config
        New-Item -ItemType Directory -Path (Join-Path $global:toolchains 'llvmorg-21.0.0') -Force | Out-Null
        Set-Location $Script:testDir
        "[version]`ndefault = \`"llvmorg-21.0.0\`"" | Set-Content -Path (Join-Path $Script:testDir '.llvmup-config')
    }

    AfterAll {
        Remove-Item -Path $Script:testDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'finds and returns default expression from config' {
        $expr = Invoke-LlvmAutoActivate -StartDirectory $Script:testDir
        $expr | Should -Be 'llvmorg-21.0.0'
    }
}
