param (
    [Parameter(Mandatory=$true)]
    [string]$LLVMVersion
)

# Define the directory where LLVM toolchains are installed
$llvmToolchainsDir = Join-Path $env:USERPROFILE ".llvm\toolchains"
$LLVMDir = Join-Path $llvmToolchainsDir $LLVMVersion

if (-not (Test-Path $LLVMDir)) {
    Write-Error "Error: LLVM version '$LLVMVersion' is not installed in $llvmToolchainsDir."
    exit 1
}

# Define paths based on the selected LLVM version
$binDir = Join-Path $LLVMDir "bin"
$clangdPath = Join-Path $binDir "clangd.exe"  # assuming clangd.exe for Windows
$compilerSearchDir = $binDir

# Extract the major version from the LLVM version string (e.g. from "llvmorg-20.1.0" extract "20")
$llvmMajorMatch = [regex]::Match($LLVMVersion, '\d+')
if ($llvmMajorMatch.Success) {
    $llvmMajor = $llvmMajorMatch.Value
} else {
    $llvmMajor = "20"
}

# Construct fallback flags for clangd (adjust paths as needed)
$fallbackFlags = "-isystem $LLVMDir\lib\clang\$llvmMajor\include -isystem $LLVMDir\include\c++\v1"

# Build the new PATH by prepending the LLVM bin directory to the existing PATH
$newPath = "$binDir;$env:PATH"

# Define the VSCode settings file location (relative to the current directory)
$vscodeDir = ".vscode"
$settingsFile = Join-Path $vscodeDir "settings.json"

# Ensure the .vscode directory exists
if (-not (Test-Path $vscodeDir)) {
    New-Item -ItemType Directory -Path $vscodeDir | Out-Null
}

# If settings.json doesn't exist, initialize it as an empty JSON object
if (-not (Test-Path $settingsFile)) {
    "{}" | Out-File -Encoding utf8 $settingsFile
}

# Read the existing JSON settings
$jsonContent = Get-Content -Raw -Path $settingsFile | ConvertFrom-Json

# Add or update the new LLVM settings using Add-Member with -Force
$jsonContent | Add-Member -MemberType NoteProperty -Name "cmake.additionalCompilerSearchDirs" -Value @($compilerSearchDir) -Force
$jsonContent | Add-Member -MemberType NoteProperty -Name "clangd.path" -Value $clangdPath -Force
$jsonContent | Add-Member -MemberType NoteProperty -Name "clangd.fallbackFlags" -Value @($fallbackFlags) -Force
$jsonContent | Add-Member -MemberType NoteProperty -Name "cmake.configureEnvironment" -Value @{ "PATH" = $newPath } -Force

# Write updated JSON back to the settings file with a reasonable depth
$jsonContent | ConvertTo-Json -Depth 100 | Out-File -Encoding utf8 $settingsFile

Write-Host "VSCode settings updated to use LLVM version '$LLVMVersion'."
Write-Host "Please reload your VSCode workspace for the changes to take effect."
