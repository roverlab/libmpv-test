#!/bin/bash

# Build Script for FriBidi Library
# Compiles FriBidi for iOS targets (device and simulator)
# Interface: build-fribidi.sh TARGET ARCH SDK_PATH

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [build-fribidi.sh] $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [build-fribidi.sh] $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [build-fribidi.sh] $1"
}

# Validate arguments
if [ $# -ne 3 ]; then
    log_error "Usage: $0 TARGET ARCH SDK_PATH"
    log_error "  TARGET   : device or simulator"
    log_error "  ARCH     : arm64"
    log_error "  SDK_PATH : Path to iOS SDK"
    exit 1
fi

TARGET=$1
ARCH=$2
SDK_PATH=$3

# Validate target
if [ "$TARGET" != "device" ] && [ "$TARGET" != "simulator" ]; then
    log_error "Invalid TARGET: $TARGET (must be 'device' or 'simulator')"
    exit 1
fi

# Validate architecture
if [ "$ARCH" != "arm64" ]; then
    log_error "Invalid ARCH: $ARCH (must be 'arm64')"
    exit 1
fi

# Validate SDK path
if [ ! -d "$SDK_PATH" ]; then
    log_error "SDK path does not exist: $SDK_PATH"
    exit 1
fi

log_info "=========================================="
log_info "Building FriBidi for iOS $TARGET"
log_info "=========================================="
log_info "Target: $TARGET"
log_info "Architecture: $ARCH"
log_info "SDK Path: $SDK_PATH"

# Read FriBidi version from versions.txt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="$SCRIPT_DIR/versions.txt"

if [ ! -f "$VERSIONS_FILE" ]; then
    log_error "versions.txt not found at: $VERSIONS_FILE"
    exit 1
fi

FRIBIDI_VERSION=$(grep "^FRIBIDI_VERSION=" "$VERSIONS_FILE" | cut -d= -f2)
if [ -z "$FRIBIDI_VERSION" ]; then
    log_error "FRIBIDI_VERSION not found in versions.txt"
    exit 1
fi

log_info "FriBidi version: $FRIBIDI_VERSION"

# Configuration
MIN_IOS_VERSION="${MIN_IOS_VERSION:-12.0}"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$PROJECT_ROOT/cache"
BUILD_DIR="$PROJECT_ROOT/build/$TARGET"
SOURCE_DIR="$CACHE_DIR/fribidi-$FRIBIDI_VERSION"
BUILD_WORK_DIR="$PROJECT_ROOT/build/work/fribidi-$TARGET"

log_info "Minimum iOS version: $MIN_IOS_VERSION"
log_info "Cache directory: $CACHE_DIR"
log_info "Build directory: $BUILD_DIR"
log_info "Source directory: $SOURCE_DIR"

# Create directories
mkdir -p "$CACHE_DIR"
mkdir -p "$BUILD_DIR/lib"
mkdir -p "$BUILD_DIR/include"
mkdir -p "$(dirname "$BUILD_WORK_DIR")"

# Download source tarball if not cached
TARBALL="fribidi-$FRIBIDI_VERSION.tar.xz"
TARBALL_PATH="$CACHE_DIR/$TARBALL"
DOWNLOAD_URL="https://github.com/fribidi/fribidi/releases/download/v$FRIBIDI_VERSION/$TARBALL"

if [ -f "$TARBALL_PATH" ]; then
    log_info "Using cached tarball: $TARBALL_PATH"
else
    log_info "Downloading FriBidi source..."
    log_info "URL: $DOWNLOAD_URL"
    
    # Download with retry logic (up to 3 attempts)
    DOWNLOAD_ATTEMPTS=0
    MAX_ATTEMPTS=3
    
    while [ $DOWNLOAD_ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        if curl -L -o "$TARBALL_PATH" "$DOWNLOAD_URL"; then
            log_info "✓ Download successful"
            break
        else
            DOWNLOAD_ATTEMPTS=$((DOWNLOAD_ATTEMPTS + 1))
            if [ $DOWNLOAD_ATTEMPTS -lt $MAX_ATTEMPTS ]; then
                log_warn "Download failed, retrying ($DOWNLOAD_ATTEMPTS/$MAX_ATTEMPTS)..."
                sleep 2
            else
                log_error "Download failed after $MAX_ATTEMPTS attempts"
                exit 1
            fi
        fi
    done
fi

# Extract source if not already extracted
if [ -d "$SOURCE_DIR" ]; then
    log_info "Using existing source directory: $SOURCE_DIR"
else
    log_info "Extracting source tarball..."
    tar -xJf "$TARBALL_PATH" -C "$CACHE_DIR"
    
    if [ ! -d "$SOURCE_DIR" ]; then
        log_error "Extraction failed: $SOURCE_DIR not found"
        exit 1
    fi
    
    log_info "✓ Source extracted to: $SOURCE_DIR"
fi

# Clean previous build work directory
if [ -d "$BUILD_WORK_DIR" ]; then
    log_info "Cleaning previous build directory..."
    rm -rf "$BUILD_WORK_DIR"
fi

# Copy source to build work directory
log_info "Preparing build directory..."
cp -R "$SOURCE_DIR" "$BUILD_WORK_DIR"

# Configure compiler and flags
export CC=$(xcrun -f clang)
export CXX=$(xcrun -f clang++)
export AR=$(xcrun -f ar)
export RANLIB=$(xcrun -f ranlib)

# Set compiler flags for iOS cross-compilation
export CFLAGS="-arch $ARCH -mios-version-min=$MIN_IOS_VERSION -isysroot $SDK_PATH -fembed-bitcode"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch $ARCH -mios-version-min=$MIN_IOS_VERSION -isysroot $SDK_PATH"

log_info "Compiler: $CC"
log_info "CFLAGS: $CFLAGS"
log_info "LDFLAGS: $LDFLAGS"

# Configure FriBidi with autotools
log_info "Configuring FriBidi..."
cd "$BUILD_WORK_DIR"

# Set host for cross-compilation
HOST_TRIPLET="aarch64-apple-darwin"

if ! ./configure \
    --host="$HOST_TRIPLET" \
    --prefix="$BUILD_DIR" \
    --enable-static \
    --disable-shared \
    --disable-docs \
    2>&1 | tee configure.log; then
    log_error "Configuration failed"
    log_error "See configure.log for details"
    tail -n 50 configure.log
    exit 1
fi

log_info "✓ Configuration successful"

# Compile FriBidi
log_info "Compiling FriBidi..."
NUM_CORES=$(sysctl -n hw.ncpu)
log_info "Using $NUM_CORES parallel jobs"

if ! make -j"$NUM_CORES" 2>&1 | tee build.log; then
    log_error "Compilation failed"
    log_error "See build.log for details"
    tail -n 50 build.log
    exit 1
fi

log_info "✓ Compilation successful"

# Install to build directory
log_info "Installing FriBidi to $BUILD_DIR..."

if ! make install 2>&1 | tee install.log; then
    log_error "Installation failed"
    log_error "See install.log for details"
    tail -n 50 install.log
    exit 1
fi

log_info "✓ Installation successful"

# Verify installation
log_info "Verifying installation..."

LIBFRIBIDI="$BUILD_DIR/lib/libfribidi.a"
if [ ! -f "$LIBFRIBIDI" ]; then
    log_error "Library not found: $LIBFRIBIDI"
    exit 1
fi

if [ ! -s "$LIBFRIBIDI" ]; then
    log_error "Library is empty: $LIBFRIBIDI"
    exit 1
fi

# Verify architecture
log_info "Verifying architecture..."
if ! lipo -info "$LIBFRIBIDI" | grep -q "$ARCH"; then
    log_error "Library does not contain $ARCH architecture"
    lipo -info "$LIBFRIBIDI"
    exit 1
fi

log_info "✓ Architecture verified: $(lipo -info "$LIBFRIBIDI")"

# Verify headers
FRIBIDI_HEADER="$BUILD_DIR/include/fribidi/fribidi.h"
if [ ! -f "$FRIBIDI_HEADER" ]; then
    log_error "Header not found: $FRIBIDI_HEADER"
    exit 1
fi

log_info "✓ Headers installed"

# Summary
log_info "=========================================="
log_info "FriBidi build completed successfully!"
log_info "=========================================="
log_info "Library: $LIBFRIBIDI"
log_info "Headers: $BUILD_DIR/include/fribidi"
log_info "Target: $TARGET ($ARCH)"

exit 0
