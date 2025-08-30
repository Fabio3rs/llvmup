# Download-Llvm.ps1: Manages the download and installation of LLVM versions from the GitHub API.
# Requirements: PowerShell v5 or later
# Usage:
#   . Download-Llvm.ps1 [version]

param (
    [Parameter(Mandatory = $false)]
    [string]$Version
)

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "This script requires PowerShell 5.0 or later. Please upgrade your PowerShell version."
    Write-Output "You can check your current version with: $PSVersionTable.PSVersion"
    exit 1
}

# Check for administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrator privileges to install LLVM."
    Write-Output "Please run PowerShell as Administrator and try again."
    exit 1
}

$apiUrl = "https://api.github.com/repos/llvm/llvm-project/releases"
Write-Output "Fetching releases from GitHub..."

try {
    $response = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing
} catch {
    Write-Error "Failed to fetch releases from GitHub. Please check your internet connection and try again."
    Write-Output "Error details: $_"
    exit 1
}

$releases = $response.Content | ConvertFrom-Json

if (-not $releases) {
    Write-Error "No releases found. This might be due to GitHub API rate limiting or temporary issues."
    Write-Output "Please try again in a few minutes."
    exit 1
}

# Build and display a list of available release tags
$releaseList = @()
$i = 1
foreach ($release in $releases) {
    $tag = $release.tag_name
    $releaseList += $tag
    $installedFlag = ""
    if (Test-Path (Join-Path $env:USERPROFILE ".llvm\toolchains\$tag")) {
        $installedFlag = " [installed]"
    }
    Write-Output "$i) $tag$installedFlag"
    $i++
}

# Function to validate and select version
function Select-Version {
    param (
        [string]$Input
    )

    # If input is a number, use it as an index (1-based)
    if ($Input -match '^\d+$') {
        $index = [int]$Input - 1
        if ($index -ge 0 -and $index -lt $releaseList.Count) {
            return $releaseList[$index]
        }
    } else {
        # Otherwise, assume it's a version tag
        if ($releaseList -contains $Input) {
            return $Input
        }
    }
    return $null
}

# Check if version was provided as parameter
if ($Version) {
    $selectedTag = Select-Version -Input $Version
    if ($selectedTag) {
        Write-Output "You selected: $selectedTag"
    } else {
        Write-Error "Invalid version selection: '$Version'"
        Write-Output "Please provide either a valid version number from the list or a valid version tag."
        exit 1
    }
} else {
    # No version provided: prompt the user
    $choice = Read-Host "Select a version by number"
    $selectedTag = Select-Version -Input $choice
    if ($selectedTag) {
        Write-Output "You selected: $selectedTag"
    } else {
        Write-Error "Invalid selection: '$choice'"
        Write-Output "Please provide either a valid version number from the list or a valid version tag."
        exit 1
    }
}

# Locate the asset that contains "win64.exe" for the selected release
$asset = $releases | Where-Object { $_.tag_name -eq $selectedTag } |
    Select-Object -ExpandProperty assets |
    Where-Object { $_.name -match "win64\.exe$" } | Select-Object -First 1

if (-not $asset) {
    Write-Error "No Windows 64-bit installer found for release $selectedTag."
    Write-Output "This might be because the release doesn't include a Windows installer or the asset naming has changed."
    Write-Output "Please try a different version or check the LLVM releases page manually."
    exit 1
}

$downloadUrl = $asset.browser_download_url
Write-Output "Download URL found: $downloadUrl"

# Define the download directory
$downloadDir = Join-Path $env:USERPROFILE "llvm_temp\$selectedTag"
if (-not (Test-Path $downloadDir)) {
    try {
        New-Item -ItemType Directory -Path $downloadDir | Out-Null
    } catch {
        Write-Error "Failed to create download directory: $downloadDir"
        Write-Output "Please check if you have write permissions in your user directory."
        exit 1
    }
}

$fileName = Split-Path $downloadUrl -Leaf
$outputFile = Join-Path $downloadDir $fileName

Write-Output "Downloading the installer..."
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $outputFile
    Write-Output "Download completed: $outputFile"
} catch {
    Write-Error "Download failed. Please check your internet connection and try again."
    Write-Output "Error details: $_"
    exit 1
}

# Define the target installation directory
$targetDir = Join-Path $env:USERPROFILE ".llvm\toolchains\$selectedTag"
$parentDir = Split-Path $targetDir -Parent
if (-not (Test-Path $parentDir)) {
    try {
        New-Item -ItemType Directory -Path $parentDir | Out-Null
    } catch {
        Write-Error "Failed to create installation directory: $parentDir"
        Write-Output "Please check if you have write permissions in your user directory."
        exit 1
    }
}

# Build the installer argument string
$arguments = "/S /D=$targetDir"

Write-Output "Starting silent installation of LLVM version '$selectedTag'..."
Write-Output "Installation directory: $targetDir"

# Start the NSIS installer with the silent and directory parameters
try {
    Start-Process -FilePath $outputFile -ArgumentList $arguments -Wait
} catch {
    Write-Error "Installation failed. Please check if you have administrator privileges and try again."
    Write-Output "Error details: $_"
    exit 1
}

Write-Output "LLVM $selectedTag installed in $targetDir."

# Clean up temporary files
try {
    Remove-Item -Path $downloadDir -Recurse -Force
} catch {
    Write-Warning "Failed to clean up temporary files in $downloadDir"
    Write-Output "You can safely delete this directory manually."
}

Write-Output "Run '. Activate-Llvm.ps1 $selectedTag' to activate the installed version."
