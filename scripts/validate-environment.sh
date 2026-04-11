#!/bin/bash

# Environment Validation Script for iOS MPV Library Build System
# Validates all prerequisites before starting the build process

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters for validation results
ERRORS=0
WARNINGS=0

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((ERRORS++))
}

echo "=========================================="
echo "iOS MPV Build Environment Validation"
echo "=========================================="
echo ""

# Check macOS version
log_info "Checking macOS version..."
MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
MACOS_MINOR=$(echo "$MACOS_VERSION" | cut -d. -f2)

log_info "macOS version: $MACOS_VERSION"

# Require macOS 11.0 (Big Sur) or later for ARM64 support
if [ "$MACOS_MAJOR" -lt 11 ]; then
    log_error "macOS 11.0 or later is required (found $MACOS_VERSION)"
else
    log_info "✓ macOS version is compatible"
fi

# Check available disk space
log_info "Checking available disk space..."
AVAILABLE_SPACE=$(df -g . | tail -1 | awk '{print $4}')
log_info "Available disk space: ${AVAILABLE_SPACE}GB"

# Require at least 10GB free space
if [ "$AVAILABLE_SPACE" -lt 10 ]; then
    log_error "At least 10GB of free disk space is required (found ${AVAILABLE_SPACE}GB)"
else
    log_info "✓ Sufficient disk space available"
fi

# Check for Xcode
log_info "Checking for Xcode..."
if ! command -v xcodebuild &> /dev/null; then
    log_error "Xcode is not installed or xcodebuild is not in PATH"
    log_error "Install Xcode from the App Store or https://developer.apple.com/xcode/"
else
    XCODE_VERSION=$(xcodebuild -version | head -1)
    log_info "✓ Found: $XCODE_VERSION"
fi

# Check for Xcode Command Line Tools
log_info "Checking for Xcode Command Line Tools..."
if ! xcode-select -p &> /dev/null; then
    log_error "Xcode Command Line Tools not installed"
    log_error "Install with: xcode-select --install"
else
    XCODE_PATH=$(xcode-select -p)
    log_info "✓ Xcode path: $XCODE_PATH"
fi

# Validate iOS SDK paths
if xcode-select -p &> /dev/null; then
    XCODE_PATH=$(xcode-select -p)
    
    log_info "Validating iOS SDK paths..."
    
    # Check device SDK
    IOS_DEVICE_SDK="$XCODE_PATH/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
    if [ -d "$IOS_DEVICE_SDK" ]; then
        log_info "✓ iOS Device SDK found: $IOS_DEVICE_SDK"
    else
        log_error "iOS Device SDK not found at: $IOS_DEVICE_SDK"
    fi
    
    # Check simulator SDK
    IOS_SIMULATOR_SDK="$XCODE_PATH/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
    if [ -d "$IOS_SIMULATOR_SDK" ]; then
        log_info "✓ iOS Simulator SDK found: $IOS_SIMULATOR_SDK"
    else
        log_error "iOS Simulator SDK not found at: $IOS_SIMULATOR_SDK"
    fi
fi

# Check for Meson
log_info "Checking for Meson build system..."
if ! command -v meson &> /dev/null; then
    log_error "Meson is not installed"
    log_error "Install with: pip3 install meson"
else
    MESON_VERSION=$(meson --version)
    log_info "✓ Found Meson version: $MESON_VERSION"
fi

# Check for Ninja
log_info "Checking for Ninja build tool..."
if ! command -v ninja &> /dev/null; then
    log_error "Ninja is not installed"
    log_error "Install with: brew install ninja"
else
    NINJA_VERSION=$(ninja --version)
    log_info "✓ Found Ninja version: $NINJA_VERSION"
fi

# Check for pkg-config
log_info "Checking for pkg-config..."
if ! command -v pkg-config &> /dev/null; then
    log_error "pkg-config is not installed"
    log_error "Install with: brew install pkg-config"
else
    PKG_CONFIG_VERSION=$(pkg-config --version)
    log_info "✓ Found pkg-config version: $PKG_CONFIG_VERSION"
fi

# Check for Python 3
log_info "Checking for Python 3..."
if ! command -v python3 &> /dev/null; then
    log_error "Python 3 is not installed"
    log_error "Install with: brew install python3"
else
    PYTHON_VERSION=$(python3 --version)
    log_info "✓ Found: $PYTHON_VERSION"
fi

# Check for Git
log_info "Checking for Git..."
if ! command -v git &> /dev/null; then
    log_error "Git is not installed"
    log_error "Install with: brew install git"
else
    GIT_VERSION=$(git --version)
    log_info "✓ Found: $GIT_VERSION"
fi

# Summary
echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    log_info "✓ All checks passed! Environment is ready for building."
    exit 0
elif [ $ERRORS -eq 0 ]; then
    log_warn "Validation completed with $WARNINGS warning(s)"
    log_warn "Build may proceed but some features might be limited"
    exit 0
else
    log_error "Validation failed with $ERRORS error(s) and $WARNINGS warning(s)"
    log_error "Please fix the errors above before proceeding with the build"
    exit 1
fi
