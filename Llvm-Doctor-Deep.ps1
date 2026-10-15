# Invoked only in a fresh PowerShell process; never alters the caller's environment.
$ErrorActionPreference = 'Stop'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('llvmup-doctor-' + [guid]::NewGuid())
try {
    $env:LLVMUP_DISABLE_AUTOACTIVATE = '1'
    $env:LLVMUP_DISABLE_PROMPT = '1'
    $env:LLVM_HOME = Join-Path $tempRoot llvm
    $env:LLVM_TOOLCHAINS_DIR = Join-Path $tempRoot toolchains
    $env:LLVM_CUSTOM_HOME = $env:LLVM_HOME
    $env:LLVM_CUSTOM_TOOLCHAINS_DIR = $env:LLVM_TOOLCHAINS_DIR
    $bin = Join-Path $env:LLVM_TOOLCHAINS_DIR 'llvmorg-18.1.8/bin'
    $null = New-Item -ItemType Directory -Path $bin -Force
    foreach ($name in @('clang.exe','clang++.exe')) { [IO.File]::WriteAllText((Join-Path $bin $name), '') }
    foreach ($name in @('_ACTIVE_LLVM','_LLVM_BACKUP','_OLD_PATH','CC','CXX','LD')) { [Environment]::SetEnvironmentVariable($name, $null) }
    Import-Module (Join-Path $PSScriptRoot 'Llvm-Functions-Core.psm1') -DisableNameChecking
    $originalPath = $env:PATH
    foreach ($custom in @($false, $true)) {
        if ($custom) { $env:CC='custom-cc'; $env:CXX='custom-cxx'; $env:LD='custom-ld' }
        $null = Invoke-LlvmActivate -Version llvmorg-18.1.8 -ToolchainsPath $env:LLVM_TOOLCHAINS_DIR
        if ($env:_ACTIVE_LLVM -ne 'llvmorg-18.1.8') { throw 'Activation failed' }
        $null = Invoke-LlvmDeactivate
        if ($env:PATH -ne $originalPath) { throw 'PATH restoration failed' }
        if ($custom) {
            if ($env:CC -ne 'custom-cc' -or $env:CXX -ne 'custom-cxx' -or $env:LD -ne 'custom-ld') { throw 'Custom state restoration failed' }
        } elseif ($env:CC -or $env:CXX -or $env:LD) { throw 'Unset state restoration failed' }
    }
    $versions = @(Invoke-LlvmMatchVersions -Expression '~18.1.8' -CandidateVersions @('llvmorg-18.1.7','llvmorg-18.1.8'))
    if ($versions.Count -ne 1 -or $versions[0] -ne 'llvmorg-18.1.8') { throw 'Range floor failed' }
    Import-Module (Join-Path $PSScriptRoot 'Llvm-Completion.psm1') -DisableNameChecking
    exit 0
} catch {
    Write-Output $_.Exception.Message
    exit 1
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
