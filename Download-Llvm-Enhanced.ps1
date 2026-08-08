# Compatibility entrypoint. The maintained implementation lives in Download-Llvm.ps1.
& (Join-Path $PSScriptRoot 'Download-Llvm.ps1') @args
