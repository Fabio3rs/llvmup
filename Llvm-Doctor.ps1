# Standalone entrypoint for partially broken facade installations.
Import-Module (Join-Path $PSScriptRoot 'Llvm-Doctor.psm1') -DisableNameChecking -ErrorAction Stop
Invoke-LlvmDoctor -Tokens @($args)
exit $LASTEXITCODE
