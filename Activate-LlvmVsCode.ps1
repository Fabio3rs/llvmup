# Activate-LlvmVsCode.ps1: Updates VSCode workspace settings for LLVM integration.
# Usage:
#   . Activate-LlvmVsCode.ps1 <version>

param (
    [Parameter(Mandatory = $true)]
    [string]$Version
)

# Check if already activated
if ($env:LLVM_ACTIVE_VERSION) {
    Write-Error "LLVM version '$env:LLVM_ACTIVE_VERSION' is already active. Please deactivate it first."
    return 1
}

$toolchainsDir = Join-Path $env:USERPROFILE ".llvm\toolchains"
$llvmDir = Join-Path $toolchainsDir $Version
$binDir = Join-Path $llvmDir "bin"

# Check if the version is installed
if (-not (Test-Path $llvmDir)) {
    Write-Error "Version '$Version' is not installed in $toolchainsDir."
    return 1
}

# Check if we're in a VSCode workspace
$vscodeDir = ".vscode"
if (-not (Test-Path $vscodeDir)) {
    Write-Error "Not in a VSCode workspace. Please run this script from your project root."
    return 1
}

# Create settings.json if it doesn't exist
$settingsPath = Join-Path $vscodeDir "settings.json"
if (-not (Test-Path $settingsPath)) {
    @{} | ConvertTo-Json | Set-Content $settingsPath
}

# Read current settings
$settings = Get-Content $settingsPath | ConvertFrom-Json

# Update settings
$settings | Add-Member -NotePropertyName "cmake.additionalCompilerSearchDirs" -NotePropertyValue @("$binDir") -Force
$settings | Add-Member -NotePropertyName "clangd.path" -NotePropertyValue (Join-Path $binDir "clangd.exe") -Force
$settings | Add-Member -NotePropertyName "clangd.fallbackFlags" -NotePropertyValue @("-I$($llvmDir)\include") -Force

# Update cmake.configureEnvironment
if (-not $settings.'cmake.configureEnvironment') {
    $settings | Add-Member -NotePropertyName "cmake.configureEnvironment" -NotePropertyValue @{} -Force
}
$settings.'cmake.configureEnvironment' | Add-Member -NotePropertyName "PATH" -NotePropertyValue "$binDir;$env:PATH" -Force

# Add debugger configuration for CMake Tools
$settings | Add-Member -NotePropertyName "cmake.debuggerPath" -NotePropertyValue (Join-Path $binDir "lldb.exe") -Force
$settings | Add-Member -NotePropertyName "cmake.debuggerEnvironment" -NotePropertyValue @{
    "PATH" = "$binDir;$env:PATH"
} -Force
$settings | Add-Member -NotePropertyName "cmake.debuggerArgs" -NotePropertyValue @(
    "--source-map=/build=${workspaceFolder}"
) -Force

# Save updated settings
$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath

# Update environment variables
$env:PATH = "$binDir;$env:PATH"
$env:CC = Join-Path $binDir "clangd.exe"
$env:CXX = Join-Path $binDir "clangd.exe"
$env:LLVM_ACTIVE_VERSION = $Version

Write-Output "VSCode workspace settings updated for LLVM version '$Version'."
Write-Output "Please reload your VSCode window for changes to take effect."
