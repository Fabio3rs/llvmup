# Download-Llvm.ps1
# This script downloads a selected LLVM release for Windows from the GitHub API
# and performs a silent installation using an NSIS-based installer.
# Requirements: PowerShell v5 or later.

$apiUrl = "https://api.github.com/repos/llvm/llvm-project/releases"
Write-Host "Fetching LLVM releases from GitHub..."

try {
    $response = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing
} catch {
    Write-Error "Failed to fetch releases from GitHub: $_"
    exit 1
}

$releases = $response.Content | ConvertFrom-Json

if (-not $releases) {
    Write-Error "No releases found."
    exit 1
}

# Build and display a list of available release tags
$releaseList = @()
$i = 1
foreach ($release in $releases) {
    $tag = $release.tag_name
    $releaseList += $tag
    Write-Host "$i) $tag"
    $i++
}

# Prompt the user to select a release by number
$choice = Read-Host "Enter the number of the release you want to download"
if (-not [int]::TryParse($choice, [ref]$null)) {
    Write-Error "Invalid selection. Please enter a number."
    exit 1
}
$index = [int]$choice - 1
if ($index -lt 0 -or $index -ge $releaseList.Count) {
    Write-Error "Selection out of range."
    exit 1
}

$selectedTag = $releaseList[$index]
Write-Host "You selected: $selectedTag"

# Set LLVMVersion to the selected tag
$LLVMVersion = $selectedTag

# Locate the asset that contains "win64.exe" for the selected release
$asset = $releases | Where-Object { $_.tag_name -eq $selectedTag } | `
    Select-Object -ExpandProperty assets | `
    Where-Object { $_.name -match "win64\.exe$" } | Select-Object -First 1

if (-not $asset) {
    Write-Error "No Windows 64-bit asset found for release $selectedTag."
    exit 1
}

$downloadUrl = $asset.browser_download_url
Write-Host "Download URL: $downloadUrl"

# Define the download directory (e.g., %USERPROFILE%\llvm_versions\<release>)
$downloadDir = Join-Path $env:USERPROFILE "llvm_versions\$selectedTag"
if (-not (Test-Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir | Out-Null
}

$fileName = Split-Path $downloadUrl -Leaf
$outputFile = Join-Path $downloadDir $fileName

Write-Host "Downloading $fileName to $downloadDir ..."
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $outputFile
    Write-Host "Download completed: $outputFile"
} catch {
    Write-Error "Download failed: $_"
    exit 1
}

# Use the downloaded file as the installer path
$InstallerPath = $outputFile

# Define the target installation directory.
# This example installs into the user's profile under ".llvm\toolchains\<version>".
$targetDir = Join-Path $env:USERPROFILE ".llvm\toolchains\$LLVMVersion"

# Ensure the parent directory exists.
$parentDir = Split-Path $targetDir -Parent
if (-not (Test-Path $parentDir)) {
    Write-Host "Creating parent directory: $parentDir"
    New-Item -ItemType Directory -Path $parentDir | Out-Null
}

# NSIS installers require the /D parameter to be the last argument with no quotes.
# $formattedTargetDir is set to $targetDir (ensure it does not contain spaces or convert to 8.3 format if needed).
$formattedTargetDir = $targetDir

# Build the installer argument string.
# /S instructs the installer to run silently.
# /D= must be the last parameter.
$arguments = "/S /D=$formattedTargetDir"

Write-Host "Starting silent installation of LLVM version '$LLVMVersion'..."
Write-Host "Installer path: $InstallerPath"
Write-Host "Installation directory: $formattedTargetDir"
Write-Host "Arguments: $arguments"

# Start the NSIS installer with the silent and directory parameters.
Start-Process -FilePath $InstallerPath -ArgumentList $arguments -Wait

Write-Host "Silent installation complete. LLVM version '$LLVMVersion' installed in $formattedTargetDir."
