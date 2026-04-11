#!/bin/bash

# Build Script for HarfBuzz Library
# Compiles HarfBuzz for iOS targets (device and simulator)
# Interface: build-harfbuzz.sh TARGET ARCH SDK_PATH

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [build-harfbuzz.sh] $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [build-harfbuzz.sh] $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [build-harfbuzz.sh] $1"
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
log_info "Building HarfBuzz for iOS $TARGET"
log_info "=========================================="
log_info "Target: $TARGET"
log_info "Architecture: $ARCH"
log_info "SDK Path: $SDK_PATH"

# Read HarfBuzz version from versions.txt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="$SCRIPT_DIR/versions.txt"

if [ ! -f "$VERSIONS_FILE" ]; then
    log_error "versions.txt not found at: $VERSIONS_FILE"
    exit 1
fi

HARFBUZZ_VERSION=$(grep "^HARFBUZZ_VERSION=" "$VERSIONS_FILE" | cut -d= -f2)
if [ -z "$HARFBUZZ_VERSION" ]; then
    log_error "HARFBUZZ_VERSION not found in versions.txt"
    exit 1
fi

log_info "HarfBuzz version: $HARFBUZZ_VERSION"

# Configuration
MIN_IOS_VERSION="${MIN_IOS_VERSION:-12.0}"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$PROJECT_ROOT/cache"
BUILD_DIR="$PROJECT_ROOT/build/$TARGET"
SOURCE_DIR="$CACHE_DIR/harfbuzz-$HARFBUZZ_VERSION"
BUILD_WORK_DIR="$PROJECT_ROOT/build/work/harfbuzz-$TARGET"

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
TARBALL="harfbuzz-$HARFBUZZ_VERSION.tar.xz"
TARBALL_PATH="$CACHE_DIR/$TARBALL"
DOWNLOAD_URL="https://github.com/harfbuzz/harfbuzz/releases/download/$HARFBUZZ_VERSION/$TARBALL"

if [ -f "$TARBALL_PATH" ]; then
    log_info "Using cached tarball: $TARBALL_PATH"
else
    log_info "Downloading HarfBuzz source..."
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

# Create build work directory
log_info "Preparing build directory..."
mkdir -p "$BUILD_WORK_DIR"

# Configure compiler and flags
export CC=$(xcrun -f clang)
export CXX=$(xcrun -f clang++)
export AR=$(xcrun -f ar)
export RANLIB=$(xcrun -f ranlib)
export STRIP=$(xcrun -f strip)

# Set compiler flags for iOS cross-compilation
export CFLAGS="-arch $ARCH -mios-version-min=$MIN_IOS_VERSION -isysroot $SDK_PATH -fembed-bitcode"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch $ARCH -mios-version-min=$MIN_IOS_VERSION -isysroot $SDK_PATH"

# Set PKG_CONFIG_PATH to find freetype dependency
export PKG_CONFIG_PATH="$BUILD_DIR/lib/pkgconfig:$PKG_CONFIG_PATH"
export PKG_CONFIG_LIBDIR="$BUILD_DIR/lib/pkgconfig"

log_info "Compiler: $CC"
log_info "CFLAGS: $CFLAGS"
log_info "LDFLAGS: $LDFLAGS"
log_info "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
log_info "PKG_CONFIG_LIBDIR: $PKG_CONFIG_LIBDIR"

# Verify freetype dependency is available
if [ ! -f "$BUILD_DIR/lib/libfreetype.a" ]; then
    log_error "FreeType dependency not found at: $BUILD_DIR/lib/libfreetype.a"
    log_error "Please build FreeType first"
    exit 1
fi

log_info "✓ FreeType dependency found"

# Configure HarfBuzz with Meson
log_info "Configuring HarfBuzz with Meson..."
cd "$BUILD_WORK_DIR"

# Create Meson cross-file for iOS
CROSS_FILE="$BUILD_WORK_DIR/ios-cross.txt"
cat > "$CROSS_FILE" << EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
pkgconfig = 'pkg-config'

[properties]
sys_root = '$SDK_PATH'
pkg_config_libdir = '$PKG_CONFIG_PATH'
c_args = ['-arch', '$ARCH', '-mios-version-min=$MIN_IOS_VERSION', '-fembed-bitcode']
cpp_args = ['-arch', '$ARCH', '-mios-version-min=$MIN_IOS_VERSION', '-fembed-bitcode']
c_link_args = ['-arch', '$ARCH', '-mios-version-min=$MIN_IOS_VERSION']
cpp_link_args = ['-arch', '$ARCH', '-mios-version-min=$MIN_IOS_VERSION']

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'
EOF

log_info "Created Meson cross-file: $CROSS_FILE"

# Configure with Meson
MESON_ARGS=(
    --cross-file="$CROSS_FILE"
    --prefix="$BUILD_DIR"
    --default-library=static
    -Dfreetype=enabled
    -Dglib=disabled
    -Dgobject=disabled
    -Dcairo=disabled
    -Dicu=disabled
    -Dgraphite=disabled
    -Dtests=disabled
    -Ddocs=disabled
    -Dbenchmark=disabled
)

meson setup "${MESON_ARGS[@]}" "$SOURCE_DIR" 2>&1 | tee configure.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "Meson configuration failed"
    log_error "See configure.log for details"
    tail -n 50 configure.log
    exit 1
fi

log_info "✓ Configuration successful"

# Compile HarfBuzz
log_info "Compiling HarfBuzz..."
NUM_CORES=$(sysctl -n hw.ncpu)
log_info "Using $NUM_CORES parallel jobs"

meson compile -j"$NUM_CORES" 2>&1 | tee build.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "Compilation failed"
    log_error "See build.log for details"
    tail -n 50 build.log
    exit 1
fi

log_info "✓ Compilation successful"

# Install to build directory
log_info "Installing HarfBuzz to $BUILD_DIR..."

meson install 2>&1 | tee install.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "Installation failed"
    log_error "See install.log for details"
    tail -n 50 install.log
    exit 1
fi

log_info "✓ Installation successful"

# Verify installation
log_info "Verifying installation..."

LIBHARFBUZZ="$BUILD_DIR/lib/libharfbuzz.a"
if [ ! -f "$LIBHARFBUZZ" ]; then
    log_error "Library not found: $LIBHARFBUZZ"
    exit 1
fi

if [ ! -s "$LIBHARFBUZZ" ]; then
    log_error "Library is empty: $LIBHARFBUZZ"
    exit 1
fi

# Verify architecture
log_info "Verifying architecture..."
if ! lipo -info "$LIBHARFBUZZ" | grep -q "$ARCH"; then
    log_error "Library does not contain $ARCH architecture"
    lipo -info "$LIBHARFBUZZ"
    exit 1
fi

log_info "✓ Architecture verified: $(lipo -info "$LIBHARFBUZZ")"

# Verify headers
HARFBUZZ_HEADER="$BUILD_DIR/include/harfbuzz/hb.h"
if [ ! -f "$HARFBUZZ_HEADER" ]; then
    log_error "Header not found: $HARFBUZZ_HEADER"
    exit 1
fi

log_info "✓ Headers installed"

# Summary
log_info "=========================================="
log_info "HarfBuzz build completed successfully!"
log_info "=========================================="
log_info "Library: $LIBHARFBUZZ"
log_info "Headers: $BUILD_DIR/include/harfbuzz"
log_info "Target: $TARGET ($ARCH)"

exit 0
