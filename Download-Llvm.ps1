# Download-Llvm.ps1: Manages the download and installation of LLVM versions from the GitHub API.
# Requirements: PowerShell v5 or later
# Usage:
#   . Download-Llvm.ps1 [version]

param (
    [Parameter(Mandatory = $false)]
    [string]$Version
)

$apiUrl = "https://api.github.com/repos/llvm/llvm-project/releases"
Write-Output "Fetching releases..."

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
        Write-Error "Invalid selection."
        exit 1
    }
} else {
    # No version provided: prompt the user
    $choice = Read-Host "Select a version by number"
    $selectedTag = Select-Version -Input $choice
    if ($selectedTag) {
        Write-Output "You selected: $selectedTag"
    } else {
        Write-Error "Invalid selection."
        exit 1
    }
}

# Locate the asset that contains "win64.exe" for the selected release
$asset = $releases | Where-Object { $_.tag_name -eq $selectedTag } |
    Select-Object -ExpandProperty assets |
    Where-Object { $_.name -match "win64\.exe$" } | Select-Object -First 1

if (-not $asset) {
    Write-Error "No Windows 64-bit asset found for release $selectedTag."
    exit 1
}

$downloadUrl = $asset.browser_download_url
Write-Output "Download URL found: $downloadUrl"

# Define the download directory
$downloadDir = Join-Path $env:USERPROFILE "llvm_temp\$selectedTag"
if (-not (Test-Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir | Out-Null
}

$fileName = Split-Path $downloadUrl -Leaf
$outputFile = Join-Path $downloadDir $fileName

Write-Output "Downloading the asset..."
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $outputFile
    Write-Output "Download completed: $outputFile"
} catch {
    Write-Error "Download failed: $_"
    exit 1
}

# Define the target installation directory
$targetDir = Join-Path $env:USERPROFILE ".llvm\toolchains\$selectedTag"
$parentDir = Split-Path $targetDir -Parent
if (-not (Test-Path $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir | Out-Null
}

# Build the installer argument string
$arguments = "/S /D=$targetDir"

Write-Output "Starting silent installation of LLVM version '$selectedTag'..."
Write-Output "Installation directory: $targetDir"

# Start the NSIS installer with the silent and directory parameters
Start-Process -FilePath $outputFile -ArgumentList $arguments -Wait

Write-Output "LLVM $selectedTag installed in $targetDir."

# Clean up temporary files
Remove-Item -Path $downloadDir -Recurse -Force

Write-Output "Run '. Activate-Llvm.ps1 $selectedTag' to activate the installed version."
