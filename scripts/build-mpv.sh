#!/bin/bash

# Build Script for MPV Library
# Compiles MPV for iOS targets (device and simulator)
# Interface: build-mpv.sh TARGET ARCH SDK_PATH DEPS_PATH

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [build-mpv.sh] $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [build-mpv.sh] $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [build-mpv.sh] $1"
}

# Validate arguments
if [ $# -ne 4 ]; then
    log_error "Usage: $0 TARGET ARCH SDK_PATH DEPS_PATH"
    log_error "  TARGET    : device or simulator"
    log_error "  ARCH      : arm64"
    log_error "  SDK_PATH  : Path to iOS SDK"
    log_error "  DEPS_PATH : Path to compiled dependencies"
    exit 1
fi

TARGET=$1
ARCH=$2
SDK_PATH=$3
DEPS_PATH=$4

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

# Validate dependencies path
if [ ! -d "$DEPS_PATH" ]; then
    log_error "Dependencies path does not exist: $DEPS_PATH"
    exit 1
fi

log_info "=========================================="
log_info "Building MPV for iOS $TARGET"
log_info "=========================================="
log_info "Target: $TARGET"
log_info "Architecture: $ARCH"
log_info "SDK Path: $SDK_PATH"
log_info "Dependencies Path: $DEPS_PATH"

# Read MPV version from versions.txt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="$SCRIPT_DIR/versions.txt"

if [ ! -f "$VERSIONS_FILE" ]; then
    log_error "versions.txt not found at: $VERSIONS_FILE"
    exit 1
fi

MPV_VERSION=$(grep "^MPV_VERSION=" "$VERSIONS_FILE" | cut -d= -f2)
if [ -z "$MPV_VERSION" ]; then
    log_error "MPV_VERSION not found in versions.txt"
    exit 1
fi

log_info "MPV version: $MPV_VERSION"

# Configuration
MIN_IOS_VERSION="${MIN_IOS_VERSION:-12.0}"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$PROJECT_ROOT/cache"
BUILD_DIR="$PROJECT_ROOT/build/$TARGET"
SOURCE_DIR="$CACHE_DIR/mpv-$MPV_VERSION"
BUILD_WORK_DIR="$PROJECT_ROOT/build/work/mpv-$TARGET"

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
TARBALL="v$MPV_VERSION.tar.gz"
TARBALL_PATH="$CACHE_DIR/$TARBALL"
DOWNLOAD_URL="https://github.com/mpv-player/mpv/archive/refs/tags/$TARBALL"

if [ -f "$TARBALL_PATH" ]; then
    log_info "Using cached tarball: $TARBALL_PATH"
else
    log_info "Downloading MPV source..."
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
    tar -xzf "$TARBALL_PATH" -C "$CACHE_DIR"
    
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

# Verify dependencies are available
log_info "Verifying dependencies..."

if [ ! -f "$DEPS_PATH/lib/libavcodec.a" ]; then
    log_error "FFmpeg dependency not found at: $DEPS_PATH/lib/libavcodec.a"
    log_error "Please build FFmpeg first"
    exit 1
fi
log_info "✓ FFmpeg dependency found"

if [ ! -f "$DEPS_PATH/lib/libass.a" ]; then
    log_error "libass dependency not found at: $DEPS_PATH/lib/libass.a"
    log_error "Please build libass first"
    exit 1
fi
log_info "✓ libass dependency found"

# Set PKG_CONFIG_PATH to find all dependencies
export PKG_CONFIG_PATH="$DEPS_PATH/lib/pkgconfig"
log_info "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"

# Generate or use existing Meson cross-file
CROSS_FILE="$PROJECT_ROOT/build/ios-$TARGET-cross.txt"

if [ ! -f "$CROSS_FILE" ]; then
    log_info "Generating Meson cross-file..."
    
    # Generate cross-file using the generate-cross-file.sh script
    if [ -f "$SCRIPT_DIR/generate-cross-file.sh" ]; then
        OUTPUT_DIR="$PROJECT_ROOT/build" "$SCRIPT_DIR/generate-cross-file.sh"
        
        # Rename to target-specific name
        if [ "$TARGET" = "device" ]; then
            mv "$PROJECT_ROOT/build/ios-device-cross.txt" "$CROSS_FILE" 2>/dev/null || true
        else
            mv "$PROJECT_ROOT/build/ios-simulator-cross.txt" "$CROSS_FILE" 2>/dev/null || true
        fi
    fi
    
    if [ ! -f "$CROSS_FILE" ]; then
        log_error "Failed to generate cross-file: $CROSS_FILE"
        exit 1
    fi
    
    log_info "✓ Cross-file generated: $CROSS_FILE"
else
    log_info "Using existing cross-file: $CROSS_FILE"
fi

# Configure MPV with Meson
log_info "Configuring MPV with Meson..."
cd "$BUILD_WORK_DIR"

# Meson build directory
MESON_BUILD_DIR="$BUILD_WORK_DIR/build"

# Check if meson is available
if ! command -v meson &> /dev/null; then
    log_error "Meson build system not found"
    log_error "Install with: pip3 install meson"
    exit 1
fi

# Check if ninja is available
if ! command -v ninja &> /dev/null; then
    log_error "Ninja build tool not found"
    log_error "Install with: brew install ninja"
    exit 1
fi

log_info "Meson version: $(meson --version)"
log_info "Ninja version: $(ninja --version)"

# Configure with Meson
if ! meson setup "$MESON_BUILD_DIR" \
    --cross-file="$CROSS_FILE" \
    --prefix="$BUILD_DIR" \
    --default-library=static \
    -Dlibmpv=true \
    -Dcplayer=false \
    -Dlua=disabled \
    -Djavascript=disabled \
    -Dlibarchive=disabled \
    -Dmanpage-build=disabled \
    -Dhtml-build=disabled \
    -Dpdf-build=disabled \
    2>&1 | tee configure.log; then
    log_error "Meson configuration failed"
    log_error "See configure.log for details"
    tail -n 50 configure.log
    exit 1
fi

log_info "✓ Meson configuration successful"

# Compile MPV
log_info "Compiling MPV..."

if ! meson compile -C "$MESON_BUILD_DIR" 2>&1 | tee build.log; then
    log_error "Compilation failed"
    log_error "See build.log for details"
    tail -n 50 build.log
    exit 1
fi

log_info "✓ Compilation successful"

# Install to build directory
log_info "Installing MPV to $BUILD_DIR..."

if ! meson install -C "$MESON_BUILD_DIR" 2>&1 | tee install.log; then
    log_error "Installation failed"
    log_error "See install.log for details"
    tail -n 50 install.log
    exit 1
fi

log_info "✓ Installation successful"

# Verify installation
log_info "Verifying installation..."

LIBMPV="$BUILD_DIR/lib/libmpv.a"
if [ ! -f "$LIBMPV" ]; then
    log_error "Library not found: $LIBMPV"
    exit 1
fi

if [ ! -s "$LIBMPV" ]; then
    log_error "Library is empty: $LIBMPV"
    exit 1
fi

# Verify architecture
log_info "Verifying architecture..."
if ! lipo -info "$LIBMPV" | grep -q "$ARCH"; then
    log_error "Library does not contain $ARCH architecture"
    lipo -info "$LIBMPV"
    exit 1
fi

log_info "✓ Architecture verified: $(lipo -info "$LIBMPV")"

# Verify headers
MPV_CLIENT_HEADER="$BUILD_DIR/include/mpv/client.h"
if [ ! -f "$MPV_CLIENT_HEADER" ]; then
    log_error "Header not found: $MPV_CLIENT_HEADER"
    exit 1
fi

log_info "✓ Headers installed"

# Summary
log_info "=========================================="
log_info "MPV build completed successfully!"
log_info "=========================================="
log_info "Library: $LIBMPV"
log_info "Headers: $BUILD_DIR/include/mpv"
log_info "Target: $TARGET ($ARCH)"

exit 0
