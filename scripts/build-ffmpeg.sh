#!/bin/bash

# Build Script for FFmpeg Library
# Compiles FFmpeg for iOS targets (device and simulator)
# Interface: build-ffmpeg.sh TARGET ARCH SDK_PATH

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [build-ffmpeg.sh] $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [build-ffmpeg.sh] $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [build-ffmpeg.sh] $1"
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
log_info "Building FFmpeg for iOS $TARGET"
log_info "=========================================="
log_info "Target: $TARGET"
log_info "Architecture: $ARCH"
log_info "SDK Path: $SDK_PATH"

# Read FFmpeg version from versions.txt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="$SCRIPT_DIR/versions.txt"

if [ ! -f "$VERSIONS_FILE" ]; then
    log_error "versions.txt not found at: $VERSIONS_FILE"
    exit 1
fi

FFMPEG_VERSION=$(grep "^FFMPEG_VERSION=" "$VERSIONS_FILE" | cut -d= -f2)
if [ -z "$FFMPEG_VERSION" ]; then
    log_error "FFMPEG_VERSION not found in versions.txt"
    exit 1
fi

log_info "FFmpeg version: $FFMPEG_VERSION"

# Configuration
MIN_IOS_VERSION="${MIN_IOS_VERSION:-12.0}"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$PROJECT_ROOT/cache"
BUILD_DIR="$PROJECT_ROOT/build/$TARGET"
SOURCE_DIR="$CACHE_DIR/ffmpeg-$FFMPEG_VERSION"
BUILD_WORK_DIR="$PROJECT_ROOT/build/work/ffmpeg-$TARGET"

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
TARBALL="ffmpeg-$FFMPEG_VERSION.tar.xz"
TARBALL_PATH="$CACHE_DIR/$TARBALL"
DOWNLOAD_URL="https://ffmpeg.org/releases/$TARBALL"

if [ -f "$TARBALL_PATH" ]; then
    log_info "Using cached tarball: $TARBALL_PATH"
else
    log_info "Downloading FFmpeg source..."
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
export STRIP=$(xcrun -f strip)

# Set compiler flags for iOS cross-compilation
# For simulator, use -mios-simulator-version-min instead of -mios-version-min
if [ "$TARGET" = "simulator" ]; then
    export CFLAGS="-arch $ARCH -mios-simulator-version-min=$MIN_IOS_VERSION -isysroot $SDK_PATH"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-arch $ARCH -mios-simulator-version-min=$MIN_IOS_VERSION -isysroot $SDK_PATH"
else
    export CFLAGS="-arch $ARCH -mios-version-min=$MIN_IOS_VERSION -isysroot $SDK_PATH -fembed-bitcode"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-arch $ARCH -mios-version-min=$MIN_IOS_VERSION -isysroot $SDK_PATH"
fi

log_info "Compiler: $CC"
log_info "CFLAGS: $CFLAGS"
log_info "LDFLAGS: $LDFLAGS"

# Configure FFmpeg
log_info "Configuring FFmpeg..."
cd "$BUILD_WORK_DIR"

# Set target OS and architecture for FFmpeg
if [ "$TARGET" = "simulator" ]; then
    FFMPEG_TARGET_OS="darwin"
else
    FFMPEG_TARGET_OS="darwin"
fi

# FFmpeg configure flags
CONFIGURE_FLAGS=(
    --prefix="$BUILD_DIR"
    --enable-cross-compile
    --target-os="$FFMPEG_TARGET_OS"
    --arch="$ARCH"
    --cc="$CC"
    --cxx="$CXX"
    --ar="$AR"
    --ranlib="$RANLIB"
    --strip="$STRIP"
    --sysroot="$SDK_PATH"
    --extra-cflags="$CFLAGS"
    --extra-cxxflags="$CXXFLAGS"
    --extra-ldflags="$LDFLAGS"
    
    # Build configuration
    --enable-static
    --disable-shared
    --enable-pic
    
    # Disable programs (we only need libraries)
    --disable-programs
    --disable-ffmpeg
    --disable-ffplay
    --disable-ffprobe
    
    # Disable documentation
    --disable-doc
    --disable-htmlpages
    --disable-manpages
    --disable-podpages
    --disable-txtpages
    
    # Disable debug
    --disable-debug
    
    # Disable incompatible features for iOS
    --disable-indev=avfoundation
    --disable-outdev=audiotoolbox
    --disable-videotoolbox
    --disable-audiotoolbox
    --disable-appkit
    --disable-coreimage
    --disable-avfoundation
    --disable-securetransport
    
    # Disable unnecessary components
    --disable-iconv
    --disable-lzma
    --disable-bzlib
    --disable-zlib
    
    # Enable required protocols
    --enable-protocol=file
    --enable-protocol=http
    --enable-protocol=https
    --enable-protocol=tcp
    --enable-protocol=udp
    --enable-protocol=rtp
    
    # Enable required demuxers (containers)
    --enable-demuxer=matroska
    --enable-demuxer=mov
    --enable-demuxer=mp3
    --enable-demuxer=aac
    --enable-demuxer=flac
    --enable-demuxer=ogg
    --enable-demuxer=wav
    --enable-demuxer=avi
    --enable-demuxer=mpegts
    --enable-demuxer=mpegps
    --enable-demuxer=webm_dash_manifest
    
    # Enable required decoders (video)
    --enable-decoder=h264
    --enable-decoder=hevc
    --enable-decoder=vp8
    --enable-decoder=vp9
    --enable-decoder=av1
    --enable-decoder=mpeg2video
    --enable-decoder=mpeg4
    --enable-decoder=theora
    
    # Enable required decoders (audio)
    --enable-decoder=aac
    --enable-decoder=mp3
    --enable-decoder=mp3float
    --enable-decoder=flac
    --enable-decoder=vorbis
    --enable-decoder=opus
    --enable-decoder=ac3
    --enable-decoder=eac3
    --enable-decoder=dca
    --enable-decoder=pcm_s16le
    --enable-decoder=pcm_s24le
    --enable-decoder=pcm_s32le
    
    # Enable required parsers
    --enable-parser=h264
    --enable-parser=hevc
    --enable-parser=vp8
    --enable-parser=vp9
    --enable-parser=aac
    --enable-parser=mp3
    --enable-parser=opus
    --enable-parser=vorbis
    
    # Enable required filters
    --enable-filter=scale
    --enable-filter=format
    --enable-filter=aformat
    --enable-filter=aresample
    
    # Disable hardware acceleration (not compatible with iOS cross-compile)
    --disable-hwaccels
    
    # Disable external libraries
    --disable-xlib
    --disable-libxcb
    --disable-libxcb-shm
    --disable-libxcb-xfixes
    --disable-libxcb-shape
)

if ! ./configure "${CONFIGURE_FLAGS[@]}" 2>&1 | tee configure.log; then
    log_error "Configuration failed"
    log_error "See configure.log for details"
    tail -n 50 configure.log
    exit 1
fi

log_info "✓ Configuration successful"

# Compile FFmpeg
log_info "Compiling FFmpeg..."
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
log_info "Installing FFmpeg to $BUILD_DIR..."

if ! make install 2>&1 | tee install.log; then
    log_error "Installation failed"
    log_error "See install.log for details"
    tail -n 50 install.log
    exit 1
fi

log_info "✓ Installation successful"

# Verify installation
log_info "Verifying installation..."

# Check for main FFmpeg libraries
LIBAVCODEC="$BUILD_DIR/lib/libavcodec.a"
LIBAVFORMAT="$BUILD_DIR/lib/libavformat.a"
LIBAVUTIL="$BUILD_DIR/lib/libavutil.a"
LIBSWSCALE="$BUILD_DIR/lib/libswscale.a"
LIBSWRESAMPLE="$BUILD_DIR/lib/libswresample.a"

for LIB in "$LIBAVCODEC" "$LIBAVFORMAT" "$LIBAVUTIL" "$LIBSWSCALE" "$LIBSWRESAMPLE"; do
    if [ ! -f "$LIB" ]; then
        log_error "Library not found: $LIB"
        exit 1
    fi
    
    if [ ! -s "$LIB" ]; then
        log_error "Library is empty: $LIB"
        exit 1
    fi
    
    # Verify architecture
    if ! lipo -info "$LIB" | grep -q "$ARCH"; then
        log_error "Library does not contain $ARCH architecture: $LIB"
        lipo -info "$LIB"
        exit 1
    fi
    
    log_info "✓ Verified: $(basename "$LIB")"
done

log_info "✓ All libraries verified"

# Verify headers
AVCODEC_HEADER="$BUILD_DIR/include/libavcodec/avcodec.h"
if [ ! -f "$AVCODEC_HEADER" ]; then
    log_error "Header not found: $AVCODEC_HEADER"
    exit 1
fi

log_info "✓ Headers installed"

# Summary
log_info "=========================================="
log_info "FFmpeg build completed successfully!"
log_info "=========================================="
log_info "Libraries:"
log_info "  - libavcodec.a"
log_info "  - libavformat.a"
log_info "  - libavutil.a"
log_info "  - libswscale.a"
log_info "  - libswresample.a"
log_info "Headers: $BUILD_DIR/include"
log_info "Target: $TARGET ($ARCH)"

exit 0
