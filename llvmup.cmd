@echo off
setlocal
set "LLVMUP_ROOT=%~dp0"
if "%LLVMUP_ROOT:~-1%"=="\" set "LLVMUP_ROOT=%LLVMUP_ROOT:~0,-1%"
set "LLVMUP_CLI=%LLVMUP_ROOT%\libexec\pwsh\llvmup-cli.ps1"

where pwsh.exe >nul 2>nul
if errorlevel 1 goto :use_winps
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%LLVMUP_CLI%" %*
exit /b %ERRORLEVEL%

:use_winps
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LLVMUP_CLI%" %*
exit /b %ERRORLEVEL%
