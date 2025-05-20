#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print status messages
print_status() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}==>${NC} $1"
}

print_error() {
    echo -e "${RED}==>${NC} $1"
}

# Check for required commands
if ! command_exists bats; then
    print_error "BATS is not installed"
    print_warning "Please run ./scripts/setup_dev.sh first"
    exit 1
fi

if ! command_exists jq; then
    print_error "jq is not installed"
    print_warning "Please install jq: sudo apt-get install jq"
    exit 1
fi

# Run BATS tests
print_status "Running BATS tests..."
bats --tap tests/unit/*.bats
BATS_RESULT=$?

# Run Pester tests if PowerShell is available
if command_exists pwsh; then
    print_status "Running Pester tests..."
    pwsh -Command "Import-Module Pester; \$result = Invoke-Pester tests/unit/*.Tests.ps1 -Output Detailed -PassThru; exit \$result.FailedCount"
    PESTER_RESULT=$?
else
    print_warning "PowerShell not found. Skipping Pester tests."
    PESTER_RESULT=0
fi

# Check results
if [ $BATS_RESULT -ne 0 ] || [ $PESTER_RESULT -ne 0 ]; then
    print_error "Some tests failed"
    if [ $BATS_RESULT -ne 0 ]; then
        print_error "BATS tests failed"
    fi
    if [ $PESTER_RESULT -ne 0 ]; then
        print_error "Pester tests failed"
    fi
    exit 1
else
    print_status "All tests passed!"
    exit 0
fi 