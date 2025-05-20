#!/bin/bash
# llvm_prebuilt.sh: Manages the download and installation of LLVM versions from the GitHub API.
# Requirements: curl, jq, tar

# Check if required commands are installed
command -v curl >/dev/null 2>&1 || { echo "The curl command is necessary, but it is not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "The jq command is necessary, but it is not installed. Aborting."; exit 1; }

# GitHub API URL for llvm-project releases
API_URL="https://api.github.com/repos/llvm/llvm-project/releases"

echo "Fetching releases..."
RELEASES=$(curl -s "$API_URL")

if [ -z "$RELEASES" ]; then
    echo "No releases found or error fetching data."
    exit 1
fi

# Extract available tags (versions)
VERSIONS=$(echo "$RELEASES" | jq -r '.[].tag_name')
IFS=$'\n' read -rd '' -a versionList <<<"$VERSIONS"

if [ ${#versionList[@]} -eq 0 ]; then
    echo "No versions found."
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
        return 1
    fi
}

# Check if an argument is passed
if [ "$#" -ge 1 ]; then
    input="$1"
    if select_version "$input"; then
        echo "You selected: $SELECTED_VERSION"
    else
        echo "Invalid selection."
        exit 1
    fi
else
    # No argument provided: prompt the user
    read -p "Select a version by number: " choice
    if select_version "$choice"; then
        echo "You selected: $SELECTED_VERSION"
    else
        echo "Invalid selection."
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
    echo "No asset found for Linux (X64) in version $SELECTED_VERSION."
    exit 1
fi

echo "Download URL found: $ASSET_URL"

# Define directories: temporary area and final installation directory
TEMP_DIR="$HOME/llvm_temp/$SELECTED_VERSION"
mkdir -p "$TEMP_DIR"

DEST_FILE="$TEMP_DIR/$(basename "$ASSET_URL")"
echo "Downloading the asset..."
curl -L "$ASSET_URL" -o "$DEST_FILE"

echo "Download completed: $DEST_FILE"
echo "Extracting the file..."
tar -xvf "$DEST_FILE" -C "$TEMP_DIR"

# Identify the extracted folder (assuming the tarball contains a single main folder)
EXTRACTED_DIR=$(tar -tf "$DEST_FILE" | head -1 | cut -d/ -f1)
echo "Extracted directory: $EXTRACTED_DIR"

# Define the final installation directory (used by the activation script)
LLVM_TOOLCHAINS_DIR="$HOME/.llvm/toolchains"
TARGET_DIR="$LLVM_TOOLCHAINS_DIR/$SELECTED_VERSION"
mkdir -p "$LLVM_TOOLCHAINS_DIR"

# Move the extracted folder to the final directory
mv "$TEMP_DIR/$EXTRACTED_DIR" "$TARGET_DIR"

echo "LLVM $SELECTED_VERSION installed in $TARGET_DIR."

# Clean up temporary files
rm -rf "$TEMP_DIR"

echo "Run 'source activate_llvm.sh $SELECTED_VERSION' to activate the installed version."

