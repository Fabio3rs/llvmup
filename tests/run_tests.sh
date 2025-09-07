#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Enable verbose output by default for better debugging
VERBOSE=1

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

print_info() {
    echo -e "${BLUE}==>${NC} $1"
}

print_verbose() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1"
    fi
}

# Check for required commands
print_status "Checking dependencies..."
print_verbose "Looking for required tools: bats, jq"

if ! command_exists bats; then
    print_error "BATS is not installed"
    print_warning "Please run ./scripts/setup_dev.sh first"
    exit 1
else
    print_verbose "BATS found: $(which bats)"
fi

if ! command_exists jq; then
    print_error "jq is not installed"
    print_warning "Please install jq: sudo apt-get install jq"
    exit 1
else
    print_verbose "jq found: $(which jq)"
fi

print_info "All dependencies are available"

# Run BATS tests
print_status "Running BATS tests in VERBOSE mode..."
print_info "This will provide detailed output for better debugging"
print_verbose "Available test files:"

if [ "$VERBOSE" -eq 1 ]; then
    ls -la tests/unit/*.bats 2>/dev/null || print_warning "No unit test files found"
    if [ -d "tests/integration" ]; then
        ls -la tests/integration/*.bats 2>/dev/null || print_verbose "No integration test files found"
    fi
fi

echo ""
print_status "Running individual test suites with verbose output..."
print_info "Each test will show detailed progress and timing information"

# Run tests individually for better error reporting
test_files=(
    "tests/unit/test_llvm_functions.bats"
    "tests/unit/test_llvm_activate.bats"
    "tests/unit/test_llvm_deactivate.bats"
    "tests/unit/test_llvm_prebuilt.bats"
    "tests/unit/test_llvm_vscode_activate.bats"
    "tests/unit/test_llvmup.bats"
    "tests/unit/test_version_expressions.bats"
    "tests/unit/test_completion_enhanced.bats"
    "tests/unit/test_enhanced_config.bats"
    "tests/unit/test_install_customization.bats"
    "tests/unit/test_libc_wno_error_flag.bats"
    "tests/unit/test_llvm_build_enhanced.bats"
    "tests/unit/test_llvm_config.bats"
    "tests/unit/test_llvmup_config_activate.bats"
    "tests/unit/test_llvmup_enhanced.bats"
    "tests/unit/test_llvmup_libc_wno_error.bats"
    "tests/unit/test_project_config.bats"
    "tests/unit/test_safe_profile_removal.bats"
)

# Add integration tests if they exist
if [ -d "tests/integration" ]; then
    for integration_test in tests/integration/*.bats; do
        if [ -f "$integration_test" ]; then
            test_files+=("$integration_test")
        fi
    done
fi

failed_tests=()
passed_tests=()

for test_file in "${test_files[@]}"; do
    if [ -f "$test_file" ]; then
        print_status "Running $(basename "$test_file")..."
        print_verbose "Test file: $test_file"

        # Always run in verbose mode with timing information
        start_time=$(date +%s)
        if bats --verbose-run --timing "$test_file"; then
            end_time=$(date +%s)
            duration=$((end_time - start_time))
            passed_tests+=("$test_file")
            print_info "✅ $(basename "$test_file") PASSED (${duration}s)"
        else
            end_time=$(date +%s)
            duration=$((end_time - start_time))
            failed_tests+=("$test_file")
            print_error "❌ $(basename "$test_file") FAILED (${duration}s)"
        fi
        echo ""
    else
        print_warning "Test file not found: $test_file"
    fi
done

# Summary
echo "==============================================="
print_status "TEST SUMMARY"
echo "==============================================="

if [ ${#failed_tests[@]} -eq 0 ]; then
    print_status "🎉 All BATS test suites passed! (${#passed_tests[@]} suites)"
    print_info "No failures detected in any test suite"
    BATS_RESULT=0
else
    print_error "💥 Some BATS test suites failed:"
    for failed_test in "${failed_tests[@]}"; do
        print_error "  ❌ $(basename "$failed_test")"
    done
    print_info "✅ Passed test suites: ${#passed_tests[@]}"
    print_error "❌ Failed test suites: ${#failed_tests[@]}"
    print_warning "Review the verbose output above for specific failure details"
    BATS_RESULT=1
fi

echo "==============================================="

# Run Pester tests if PowerShell is available
if command_exists pwsh; then
    print_status "Running PowerShell Pester tests..."
    print_verbose "PowerShell found: $(which pwsh)"
    pwsh -Command "Import-Module Pester; \$result = Invoke-Pester tests/unit/*.Tests.ps1 -Output Detailed -PassThru; exit \$result.FailedCount"
    PESTER_RESULT=$?
    if [ $PESTER_RESULT -eq 0 ]; then
        print_info "✅ PowerShell tests PASSED"
    else
        print_error "❌ PowerShell tests FAILED"
    fi
else
    print_warning "PowerShell not found. Skipping Pester tests."
    print_verbose "To run PowerShell tests, install PowerShell: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux"
    PESTER_RESULT=0
fi

echo "==============================================="

# Final results
print_status "FINAL TEST RESULTS"
echo "==============================================="

if [ $BATS_RESULT -ne 0 ] || [ $PESTER_RESULT -ne 0 ]; then
    print_error "❌ SOME TESTS FAILED"
    if [ $BATS_RESULT -ne 0 ]; then
        print_error "   • BATS tests failed"
    fi
    if [ $PESTER_RESULT -ne 0 ]; then
        print_error "   • PowerShell/Pester tests failed"
    fi
    print_warning "Review the detailed output above to identify and fix issues"
    print_info "Tip: Run individual test files to isolate problems:"
    print_info "  bats --verbose-run tests/unit/test_specific_file.bats"
    echo "==============================================="
    exit 1
else
    print_status "🎉 ALL TESTS PASSED!"
    print_info "Your LLVM manager is working correctly"
    echo "==============================================="
    exit 0
fi 