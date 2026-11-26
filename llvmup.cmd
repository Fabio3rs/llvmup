@echo off
setlocal
set "LLVMUP_ROOT=%~dp0"
if "%LLVMUP_ROOT:~-1%"=="\" set "LLVMUP_ROOT=%LLVMUP_ROOT:~0,-1%"
set "LLVMUP_CLI=%LLVMUP_ROOT%\libexec\pwsh\llvmup-cli.ps1"

for %%I in (pwsh.exe) do set "LLVMUP_PWSH=%%~$PATH:I"
if not defined LLVMUP_PWSH goto :use_winps
"%LLVMUP_PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%LLVMUP_CLI%" --llvmup-args %*
exit /b %ERRORLEVEL%

:use_winps
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%LLVMUP_CLI%" --llvmup-args %*
exit /b %ERRORLEVEL%
