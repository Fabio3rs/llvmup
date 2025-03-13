#!/bin/bash
# build_llvm_source.sh
#
# This script lists available LLVM release tags from the official repository,
# prompts the user to select one, clones the selected release (with depth 1)
# into ~/.llvm/sources/<version>, runs CMake with Ninja to build LLVM with
# -march=native and -mtune=native, and installs the built LLVM to
# ~/.llvm/toolchains/source-<version>.
#
# Requirements: git, cmake, ninja, and a modern C/C++ toolchain.
#
# Usage:
#   ./build_llvm_source.sh

set -e

REPO_URL="https://github.com/llvm/llvm-project.git"
SOURCES_DIR="$HOME/.llvm/sources"
TOOLCHAINS_DIR="$HOME/.llvm/toolchains"

echo "Fetching available LLVM release tags from the repository..."
# Fetch tags from remote and filter for those starting with llvmorg-
tags=$(git ls-remote --tags "$REPO_URL" | grep 'refs/tags/llvmorg-' | sed 's/.*refs\/tags\///; s/\^{}//' | sort -V)

if [ -z "$tags" ]; then
  echo "No tags found."
  exit 1
fi

# Read tags into an array using readarray (Bash 4+)
readarray -t tagArray <<< "$tags"

echo "Available LLVM releases:"
i=1
for tag in "${tagArray[@]}"; do
  echo "$i) $tag"
  ((i++))
done

read -p "Enter the number of the release you want to build: " choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#tagArray[@]} ]; then
  echo "Invalid selection."
  exit 1
fi

selectedTag="${tagArray[$((choice-1))]}"
echo "You selected: $selectedTag"

# Prepare source directory
targetSourceDir="$SOURCES_DIR/$selectedTag"
mkdir -p "$SOURCES_DIR"

if [ -d "$targetSourceDir" ]; then
  echo "Source for version $selectedTag already exists at $targetSourceDir."
else
  echo "Cloning LLVM project (branch/tag: $selectedTag) with depth 1..."
  git clone --depth 1 --branch "$selectedTag" "$REPO_URL" "$targetSourceDir"
fi

# Create a build directory
buildDir="$targetSourceDir/build"
mkdir -p "$buildDir"

# Define installation directory
installDir="$TOOLCHAINS_DIR/source-$selectedTag"
mkdir -p "$TOOLCHAINS_DIR"

echo "Configuring build with CMake (using Ninja generator)..."
cmake -S "$targetSourceDir/llvm" -B "$buildDir" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS="all" \
  -DCMAKE_C_FLAGS="-march=native -mtune=native" \
  -DCMAKE_CXX_FLAGS="-march=native -mtune=native" \
  -DCMAKE_INSTALL_PREFIX="$installDir"

echo "Building LLVM (this may take a while)..."
cmake --build "$buildDir" -- -j "$(nproc)"

echo "Installing LLVM to $installDir..."
cmake --build "$buildDir" --target install

echo "Build and installation complete!"
echo "LLVM version $selectedTag has been installed in $installDir."

