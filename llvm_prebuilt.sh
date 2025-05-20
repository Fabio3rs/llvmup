#!/bin/bash
# llvm_prebuilt.sh: Manages the download and installation of LLVM versions from the GitHub API.
# Requirements: curl, jq, tar

# Check if required commands are installed
command -v curl >/dev/null 2>&1 || {
    echo "Error: The 'curl' command is required but not installed."
    echo "Please install curl using your package manager:"
    echo "  Ubuntu/Debian: sudo apt-get install curl"
    echo "  Fedora: sudo dnf install curl"
    echo "  Arch Linux: sudo pacman -S curl"
    exit 1
}

command -v jq >/dev/null 2>&1 || {
    echo "Error: The 'jq' command is required but not installed."
    echo "Please install jq using your package manager:"
    echo "  Ubuntu/Debian: sudo apt-get install jq"
    echo "  Fedora: sudo dnf install jq"
    echo "  Arch Linux: sudo pacman -S jq"
    exit 1
}

# GitHub API URL for llvm-project releases
API_URL="https://api.github.com/repos/llvm/llvm-project/releases"

echo "Fetching releases from GitHub..."
RELEASES=$(curl -s "$API_URL")

if [ -z "$RELEASES" ]; then
    echo "Error: Failed to fetch releases from GitHub."
    echo "This might be due to:"
    echo "  - Internet connection issues"
    echo "  - GitHub API rate limiting"
    echo "  - Temporary GitHub service disruption"
    echo "Please check your connection and try again in a few minutes."
    exit 1
fi

# Extract available tags (versions)
VERSIONS=$(echo "$RELEASES" | jq -r '.[].tag_name')
IFS=$'\n' read -rd '' -a versionList <<<"$VERSIONS"

if [ ${#versionList[@]} -eq 0 ]; then
    echo "Error: No LLVM versions found."
    echo "This might be due to:"
    echo "  - GitHub API rate limiting"
    echo "  - Changes in the LLVM release structure"
    echo "  - Temporary GitHub service disruption"
    echo "Please try again in a few minutes."
    exit 1
fi

echo "Available versions:"
for i in "${!versionList[@]}"; do
    version="${versionList[$i]}"
    INSTALLED_FLAG=""
    if [ -d "$HOME/.llvm/toolchains/$version" ]; then
        INSTALLED_FLAG=" [installed]"
    fi
    echo "$((i+1))) $version$INSTALLED_FLAG"
done

# Function to validate and select version based on input
select_version() {
    local input="$1"
    # If input is a number, use it as an index (1-based)
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        if [ "$input" -ge 1 ] && [ "$input" -le ${#versionList[@]} ]; then
            SELECTED_VERSION="${versionList[$((input-1))]}"
            return 0
        else
            echo "Error: Invalid version number '$input'"
            echo "Please select a number between 1 and ${#versionList[@]}"
            return 1
        fi
    else
        # Otherwise, assume it's a version tag. Check if it exists in the array.
        for tag in "${versionList[@]}"; do
            if [ "$tag" = "$input" ]; then
                SELECTED_VERSION="$tag"
                return 0
            fi
        done
        echo "Error: Invalid version tag '$input'"
        echo "Please provide either a valid version number or a valid version tag from the list above."
        return 1
    fi
}

# Check if an argument is passed
if [ "$#" -ge 1 ]; then
    input="$1"
    if select_version "$input"; then
        echo "You selected: $SELECTED_VERSION"
    else
        exit 1
    fi
else
    # No argument provided: prompt the user
    read -p "Select a version by number: " choice
    if select_version "$choice"; then
        echo "You selected: $SELECTED_VERSION"
    else
        exit 1
    fi
fi

# Find the asset containing "Linux-X64.tar.xz" for the selected version
ASSET_URL=$(echo "$RELEASES" | jq -r --arg version "$SELECTED_VERSION" '
  .[] | select(.tag_name == $version) |
  .assets[] | select(.name | test("Linux-X64.tar.xz$")) |
  .browser_download_url
')

if [ -z "$ASSET_URL" ]; then
    echo "Error: No Linux X64 tarball found for version $SELECTED_VERSION."
    echo "This might be because:"
    echo "  - The release doesn't include a Linux X64 build"
    echo "  - The asset naming convention has changed"
    echo "Please try a different version or check the LLVM releases page manually."
    exit 1
fi

echo "Download URL found: $ASSET_URL"

# Define directories: temporary area and final installation directory
TEMP_DIR="$HOME/llvm_temp/$SELECTED_VERSION"
if ! mkdir -p "$TEMP_DIR"; then
    echo "Error: Failed to create temporary directory: $TEMP_DIR"
    echo "Please check if you have write permissions in your home directory."
    exit 1
fi

DEST_FILE="$TEMP_DIR/$(basename "$ASSET_URL")"
echo "Downloading the tarball..."
if ! curl -L "$ASSET_URL" -o "$DEST_FILE"; then
    echo "Error: Failed to download the tarball."
    echo "Please check your internet connection and try again."
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Download completed: $DEST_FILE"
echo "Extracting the file..."
if ! tar -xf "$DEST_FILE" -C "$TEMP_DIR"; then
    echo "Error: Failed to extract the tarball."
    echo "The downloaded file might be corrupted. Please try again."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Identify the extracted folder (assuming the tarball contains a single main folder)
EXTRACTED_DIR=$(tar -tf "$DEST_FILE" | head -1 | cut -d/ -f1)
if [ -z "$EXTRACTED_DIR" ]; then
    echo "Error: Failed to identify the extracted directory."
    echo "The tarball structure might be unexpected. Please try again."
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "Extracted directory: $EXTRACTED_DIR"

# Define the final installation directory (used by the activation script)
LLVM_TOOLCHAINS_DIR="$HOME/.llvm/toolchains"
TARGET_DIR="$LLVM_TOOLCHAINS_DIR/$SELECTED_VERSION"

# Create the toolchains directory if it doesn't exist
if ! mkdir -p "$LLVM_TOOLCHAINS_DIR"; then
    echo "Error: Failed to create toolchains directory: $LLVM_TOOLCHAINS_DIR"
    echo "Please check if you have write permissions in your home directory."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Move the extracted folder to the final directory
if ! mv "$TEMP_DIR/$EXTRACTED_DIR" "$TARGET_DIR"; then
    echo "Error: Failed to move the extracted files to the target directory."
    echo "Please check if you have write permissions in your home directory."
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "LLVM $SELECTED_VERSION installed in $TARGET_DIR."

# Clean up temporary files
if ! rm -rf "$TEMP_DIR"; then
    echo "Warning: Failed to clean up temporary files in $TEMP_DIR"
    echo "You can safely delete this directory manually."
fi

echo "Run 'source activate_llvm.sh $SELECTED_VERSION' to activate the installed version."

