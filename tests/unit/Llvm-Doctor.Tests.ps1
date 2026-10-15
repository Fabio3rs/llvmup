Describe 'Read-only LLVMUP doctor' {
    BeforeAll {
        $script:root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        Import-Module (Join-Path $script:root 'Llvm-Doctor.psm1') -Force -DisableNameChecking
    }
    BeforeEach {
        $script:saved = @{}
        foreach ($name in @('LLVM_HOME','LLVM_TOOLCHAINS_DIR','_ACTIVE_LLVM','_ACTIVE_LLVM_PATH','_LLVM_BACKUP','_OLD_PATH','LLVMUP_ACTIVE_VERSION','LLVM_ACTIVE_VERSION','CC','CXX','LD')) {
            $script:saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        $env:LLVM_HOME = Join-Path $TestDrive 'data with spaces'
        $env:LLVM_TOOLCHAINS_DIR = Join-Path $env:LLVM_HOME custom
        $null = New-Item -ItemType Directory -Path $env:LLVM_TOOLCHAINS_DIR -Force
        $script:oldLocation = Get-Location
        Set-Location $TestDrive
        '[version]', 'default = "latest"' | Set-Content .llvmup-config
    }
    AfterEach {
        Set-Location $script:oldLocation
        foreach ($name in $script:saved.Keys) { [Environment]::SetEnvironmentVariable($name, $script:saved[$name]) }
    }
    It 'produces stable JSON without an installed toolchain and remains offline' {
        Mock Invoke-RestMethod -ModuleName Llvm-Doctor { throw 'Unexpected network' }
        Mock Invoke-WebRequest -ModuleName Llvm-Doctor { throw 'Unexpected network' }
        $first = Invoke-LlvmDoctor -Tokens @('--json')
        $second = Invoke-LlvmDoctor -Tokens @('--json')
        $first | Should -BeExactly $second
        $data = $first | ConvertFrom-Json
        $data.schema_version | Should -Be 1
        $data.exit_code | Should -Be 0
        $global:LASTEXITCODE | Should -Be 0
        ($data.checks | Where-Object id -eq network.github).status | Should -Be SKIP
        Should -Invoke Invoke-RestMethod -ModuleName Llvm-Doctor -Times 0 -Exactly
        Should -Invoke Invoke-WebRequest -ModuleName Llvm-Doctor -Times 0 -Exactly
    }
    It 'diagnoses missing runtime files independently of the facade' {
        $data = Invoke-LlvmDoctor -Root $TestDrive -Tokens @('--json') | ConvertFrom-Json
        $data.exit_code | Should -Be 1
        @($data.checks | Where-Object { $_.id -eq 'installation.file' -and $_.status -eq 'FAIL' }).Count | Should -BeGreaterThan 0
    }
    It 'detects incomplete toolchains and a broken default target without deleting them' {
        $broken = Join-Path $env:LLVM_TOOLCHAINS_DIR broken
        $default = Join-Path $env:LLVM_HOME default
        $null = New-Item -ItemType Directory -Path $broken,$default -Force
        $data = Invoke-LlvmDoctor -Tokens @('--json') | ConvertFrom-Json
        ($data.checks | Where-Object id -eq toolchain.compilers).status | Should -Be FAIL
        ($data.checks | Where-Object id -eq toolchain.default).status | Should -Be FAIL
        Test-Path $broken | Should -BeTrue
        Test-Path $default | Should -BeTrue
    }
    It 'accepts lightweight custom-path compiler files without executing them' {
        $bin = Join-Path $env:LLVM_TOOLCHAINS_DIR 'llvmorg-18.1.8/bin'
        $null = New-Item -ItemType Directory -Path $bin -Force
        foreach ($name in @('clang.exe','clang++.exe')) { [IO.File]::WriteAllText((Join-Path $bin $name), 'not executable') }
        $before = @(Get-ChildItem -Recurse $env:LLVM_HOME | Select-Object FullName,Length,LastWriteTimeUtc) | ConvertTo-Json
        $data = Invoke-LlvmDoctor -Tokens @('--json') | ConvertFrom-Json
        $data.exit_code | Should -Be 0
        ($data.checks | Where-Object id -eq toolchain.compilers).status | Should -Be PASS
        $after = @(Get-ChildItem -Recurse $env:LLVM_HOME | Select-Object FullName,Length,LastWriteTimeUtc) | ConvertTo-Json
        $after | Should -BeExactly $before
    }
    It 'reports missing optional source dependencies as warnings' {
        Mock Get-Command -ModuleName Llvm-Doctor { $null } -ParameterFilter { $Name -eq 'ninja' }
        $data = Invoke-LlvmDoctor -Tokens @('--json') | ConvertFrom-Json
        ($data.checks | Where-Object id -eq dependency.ninja).status | Should -Be WARN
    }
    It 'rejects invalid project configuration without evaluating it' {
        '[version]', 'default = "$(throw ''must not run'')"' | Set-Content .llvmup-config
        $data = Invoke-LlvmDoctor -Tokens @('--json') | ConvertFrom-Json
        ($data.checks | Where-Object id -eq project.config).status | Should -Be FAIL
    }
    It 'detects an invalid active environment' {
        $env:_ACTIVE_LLVM = 'missing'
        $data = Invoke-LlvmDoctor -Tokens @('--json') | ConvertFrom-Json
        ($data.checks | Where-Object id -eq environment.active).status | Should -Be FAIL
        $env:_ACTIVE_LLVM | Should -Be missing
    }
    It 'returns argument errors in JSON even with ErrorActionPreference Stop' {
        $previous = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Stop'
            $data = Invoke-LlvmDoctor -Tokens @('--fix','--json') | ConvertFrom-Json
            $data.exit_code | Should -Be 2
            $global:LASTEXITCODE | Should -Be 2
        } finally { $ErrorActionPreference = $previous }
    }
    It 'isolates deep activation from caller environment' {
        $env:CC = 'custom compiler'
        $before = $env:PATH
        $data = Invoke-LlvmDoctor -Tokens @('--deep','--json') | ConvertFrom-Json
        ($data.checks | Where-Object id -eq deep.activation).status | Should -Be PASS
        $env:CC | Should -Be 'custom compiler'
        $env:PATH | Should -BeExactly $before
    }
    It 'integrates with the public facade without appending booleans to JSON' {
        Import-Module (Join-Path $script:root 'Llvm-Functions.psm1') -Force -DisableNameChecking
        $data = llvmup doctor --json | ConvertFrom-Json
        $data.schema_version | Should -Be 1
    }
}

Describe 'Doctor shell integration and network checks' {
    BeforeAll {
        $script:root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        Import-Module (Join-Path $script:root 'Llvm-Doctor.psm1') -Force -DisableNameChecking
    }
    It 'warns about duplicate PowerShell profile imports without editing profiles' {
        $profileFile = Join-Path $TestDrive 'profile.ps1'
        'Import-Module "C:/llvmup/Llvm-Functions.psm1"', 'Import-Module "C:/llvmup/Llvm-Functions.psm1"' | Set-Content $profileFile
        $before = Get-Content $profileFile -Raw
        InModuleScope Llvm-Doctor -Parameters @{ ProfileFile=$profileFile; Root=$script:root; DataPath=$TestDrive } {
            param($ProfileFile, $Root, $DataPath)
            $PROFILE = [pscustomobject]@{ CurrentUserCurrentHost=$ProfileFile; CurrentUserAllHosts=$ProfileFile; AllUsersCurrentHost=$ProfileFile; AllUsersAllHosts=$ProfileFile }
            $checks = [Collections.Generic.List[object]]::new()
            Get-DoctorEnvironment $checks $DataPath $Root
            ($checks | Where-Object id -eq shell.initialization).status | Should -Be WARN
        }
        Get-Content $profileFile -Raw | Should -BeExactly $before
    }
    It 'identifies missing completion without requiring an installed LLVM' {
        $data = Invoke-LlvmDoctor -Root $TestDrive -Tokens @('--json') | ConvertFrom-Json
        ($data.checks | Where-Object id -eq shell.completion).status | Should -Be FAIL
    }
    It 'uses bounded metadata and header requests only when requested' {
        Mock Invoke-RestMethod -ModuleName Llvm-Doctor { @([pscustomobject]@{tag_name='llvmorg-18.1.8'}) }
        Mock Invoke-WebRequest -ModuleName Llvm-Doctor { [pscustomobject]@{StatusCode=200} }
        $data = Invoke-LlvmDoctor -Tokens @('--network','--json') | ConvertFrom-Json
        ($data.checks | Where-Object id -eq network.github).status | Should -Be PASS
        Should -Invoke Invoke-RestMethod -ModuleName Llvm-Doctor -Times 1 -Exactly -ParameterFilter { $TimeoutSec -eq 8 }
        Should -Invoke Invoke-WebRequest -ModuleName Llvm-Doctor -Times 1 -Exactly -ParameterFilter { $TimeoutSec -eq 8 -and $Method -eq 'Head' }
    }
}
