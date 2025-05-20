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

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please do not run this script as root"
    exit 1
fi

# Install BATS if not present
if ! command_exists bats; then
    print_status "Installing BATS..."
    if command_exists apt-get; then
        # Debian/Ubuntu
        sudo apt-get update
        sudo apt-get install -y bats
    elif command_exists brew; then
        # macOS
        brew install bats-core
    else
        # Manual installation
        print_warning "Package manager not found. Installing BATS manually..."
        git clone https://github.com/bats-core/bats-core.git
        cd bats-core
        ./install.sh /usr/local
        cd ..
        rm -rf bats-core
    fi
else
    print_status "BATS is already installed"
fi

# Check for PowerShell (for Windows tests)
if ! command_exists pwsh; then
    print_warning "PowerShell not found. Windows tests will not be available locally."
    print_warning "To run Windows tests, install PowerShell: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell"
else
    print_status "PowerShell is installed"
    
    # Install Pester if PowerShell is available
    print_status "Installing Pester..."
    pwsh -Command "if (-not (Get-Module -ListAvailable -Name Pester)) { Install-Module -Name Pester -Force -SkipPublisherCheck }"
fi

# Create pre-commit hook for running tests
print_status "Setting up git hooks..."
mkdir -p .git/hooks
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
echo "Running tests before commit..."
./tests/run_tests.sh
EOF
chmod +x .git/hooks/pre-commit

print_status "Development environment setup complete!"
print_status "You can now run tests using: ./tests/run_tests.sh" 