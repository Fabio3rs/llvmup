# Activate-LlvmVsCode.ps1: Updates VSCode workspace settings for LLVM integration.
# Usage:
#   . Activate-LlvmVsCode.ps1 <version>

param (
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$toolchainsDir = Join-Path $env:USERPROFILE ".llvm\toolchains"
$llvmDir = Join-Path $toolchainsDir $Version

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
$settings | Add-Member -NotePropertyName "cmake.additionalCompilerSearchDirs" -NotePropertyValue @("$($llvmDir)\bin") -Force
$settings | Add-Member -NotePropertyName "clangd.path" -NotePropertyValue (Join-Path $llvmDir "bin\clangd.exe") -Force
$settings | Add-Member -NotePropertyName "clangd.fallbackFlags" -NotePropertyValue @("-I$($llvmDir)\include") -Force

# Update cmake.configureEnvironment
if (-not $settings.'cmake.configureEnvironment') {
    $settings | Add-Member -NotePropertyName "cmake.configureEnvironment" -NotePropertyValue @{} -Force
}
$settings.'cmake.configureEnvironment' | Add-Member -NotePropertyName "PATH" -NotePropertyValue "$($llvmDir)\bin;$env:PATH" -Force

# Save updated settings
$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath

Write-Output "VSCode workspace settings updated for LLVM version '$Version'."
Write-Output "Please reload your VSCode window for changes to take effect."
