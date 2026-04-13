#!/bin/sh
set -e

cd $SRC/mpv*

echo "Building mpv with meson (all deps as subprojects)..."
echo "  ARCH=$ARCH"
echo "  ENVIRONMENT=$ENVIRONMENT"
echo "  SDKPATH=$SDKPATH"
echo "  SCRATCH=$SCRATCH"

# Validate required environment variables
if [ -z "$ARCH" ] || [ -z "$SDKPATH" ] || [ -z "$SCRATCH" ]; then
    echo "ERROR: Required environment variables not set"
    echo "  ARCH=$ARCH"
    echo "  SDKPATH=$SDKPATH"
    echo "  SCRATCH=$SCRATCH"
    exit 1
fi

# 模拟器环境使用单独的目录
if [ "$ENVIRONMENT" = "simulator" ]; then
    ARCH_DIR="arm64-simulator"
else
    ARCH_DIR="$ARCH"
fi

# PKG_CONFIG_PATH is only needed for FFmpeg (built separately, not a subproject)
export PKG_CONFIG_PATH="$SCRATCH/$ARCH_DIR/lib/pkgconfig"
echo "  ARCH_DIR=$ARCH_DIR"
echo "  PKG_CONFIG_PATH=$PKG_CONFIG_PATH (for FFmpeg only)"

# Determine target based on architecture and environment
if [ "$ARCH" = "arm64" ]; then
    CPU_FAMILY="aarch64"
    CPU="aarch64"
    if [ "$ENVIRONMENT" = "simulator" ]; then
        TARGET_TRIPLE="arm64-apple-ios13.0-simulator"
        SDK_NAME="iphonesimulator"
    else
        TARGET_TRIPLE="arm64-apple-ios13.0"
        SDK_NAME="iphoneos"
    fi
elif [ "$ARCH" = "x86_64" ]; then
    TARGET_TRIPLE="x86_64-apple-ios13.0-simulator"
    SDK_NAME="iphonesimulator"
    CPU_FAMILY="x86_64"
    CPU="x86_64"
else
    echo "ERROR: Unsupported architecture: $ARCH"
    exit 1
fi

# Create cross-file for iOS cross-compilation
CROSS_FILE="$SCRATCH/$ARCH_DIR/mpv-cross-file.txt"
mkdir -p "$SCRATCH/$ARCH_DIR"

if [ "$ENVIRONMENT" = "simulator" ] || [ "$SDK_NAME" = "iphonesimulator" ]; then
    MIN_VERSION_FLAG="-mios-simulator-version-min=13.0"
else
    MIN_VERSION_FLAG="-miphoneos-version-min=13.0"
fi

# ---------------------------------------------------------------------------
# Cross-file: defines the HOST (target=iOS) compiler and toolchain.
# Passed to meson via --cross-file.
# ---------------------------------------------------------------------------
cat > "$CROSS_FILE" << EOF
[binaries]
c = 'clang'
cpp = 'clang++'
objc = 'clang'
objcpp = 'clang++'
ar = 'ar'
strip = 'strip'
pkg-config = 'pkg-config'

[host_machine]
system = 'darwin'
cpu_family = '$CPU_FAMILY'
cpu = '$CPU'
endian = 'little'

[properties]
needs_exe_wrapper = true

[built-in options]
prefix = '$SCRATCH/$ARCH_DIR'
libdir = 'lib'
default_library = 'static'

c_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG']
cpp_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG']
objc_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG', '-fobjc-arc']
objcpp_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG', '-fobjc-arc']
c_link_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG', '-framework', 'Foundation', '-framework', 'CoreFoundation', '-framework', 'AudioToolbox', '-framework', 'AVFoundation', '-framework', 'CoreMedia', '-framework', 'CoreVideo', '-framework', 'OpenGLES', '-framework', 'QuartzCore', '-framework', 'IOSurface']
cpp_link_args = c_link_args
objc_link_args = c_link_args
objcpp_link_args = c_link_args
EOF

echo "Cross-file created at: $CROSS_FILE"
cat "$CROSS_FILE"

# Clean previous build directory to avoid stale configuration
if [ -d "build" ]; then
    echo "Cleaning previous build directory..."
    rm -rf build
fi

# =========================================================================
# CRITICAL: Clean Environment
# `scripts/build.sh` exports IPHONEOS_DEPLOYMENT_TARGET and modifies PATH.
# This causes Apple's native clang to implicitly build iOS binaries!
# When Meson checks the build-machine compiler, the resulting binary is an
# iOS executable, which macOS cannot run. Thus: "executables are not runnable".
# To fix this, we strictly unset all Apple environment overrides.
# =========================================================================
unset IPHONEOS_DEPLOYMENT_TARGET
unset TVOS_DEPLOYMENT_TARGET
unset MACOSX_DEPLOYMENT_TARGET
unset SDKROOT
unset CFLAGS CXXFLAGS LDFLAGS AR STRIP CC CXX OBJC OBJCXX

echo "Building with perfectly clean host environment..."

export PKG_CONFIG_LIBDIR="$SCRATCH/$ARCH_DIR/lib/pkgconfig"
unset PKG_CONFIG_PATH

meson setup build \
    --cross-file "$CROSS_FILE" \
    --buildtype=release \
    --wrap-mode=forcefallback \
    -Ddefault_library=static \
    -Dcplayer=false \
    -Dgpl=false \
    -Dlibmpv=true \
    -Dlua=disabled \
    -Djavascript=disabled \
    -Dcocoa=disabled \
    -Dswift-build=disabled \
    -Dmacos-cocoa-cb=disabled \
    -Dcoreaudio=disabled \
    -Daudiounit=enabled \
    -Davfoundation=disabled \
    -Dvideotoolbox-pl=disabled \
    -Dvideotoolbox-gl=disabled \
    -Dgl=disabled \
    -Degl=disabled \
    -Dvulkan=disabled \
    -Dplain-gl=disabled \
    -Dx11=disabled \
    -Dwayland=disabled \
    -Dalsa=disabled \
    -Dios-gl=enabled \
    -Dmanpage-build=disabled \
    -Dhtml-build=disabled \
    -Dpdf-build=disabled \
    -Dlibplacebo:opengl=enabled \
    -Dlibplacebo:vulkan=disabled \
    -Dlibplacebo:glslang=disabled \
    -Dlibplacebo:shaderc=disabled \
    -Dlibplacebo:lcms=disabled \
    -Dlibplacebo:dovi=disabled \
    -Dlibplacebo:libdovi=disabled \
    -Dlibplacebo:xxhash=disabled \
    -Diconv=disabled \
    -Dlibarchive=disabled \
    -Duchardet=enabled \
    -Dlcms2=disabled \
    -Dmacos-media-player=disabled \
    -Djpeg=disabled \
    -Dlibass:coretext=enabled \
    -Dlibass:fontconfig=disabled \
    -Dlibass:asm=disabled \
    -Dlibass:directwrite=disabled \
    -Dfreetype2:png=disabled \
    -Dfreetype2:bzip2=disabled \
    -Dfreetype2:brotli=disabled \
    -Dharfbuzz:glib=disabled \
    -Dharfbuzz:icu=disabled \
    -Dharfbuzz:cairo=disabled \
    -Dharfbuzz:freetype=enabled \
    -Dfribidi:tests=false 

ninja -C build -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
ninja -C build install

# Copy libmpv.a to lib directory
find "$SCRATCH/$ARCH_DIR" -name "libmpv.a" -exec cp {} "$SCRATCH/$ARCH_DIR/lib/" \; 2>/dev/null || true

# Copy subproject static libraries that meson does NOT install to the prefix.
echo "=== Copying subproject static libs ==="
echo "=== All .a files in meson build tree ==="
find "$(pwd)/build" -name "*.a" -type f | sort
echo ""

find "$(pwd)/build" -name "*.a" -type f | while read lib; do
    libname=$(basename "$lib")
    dest="$SCRATCH/$ARCH_DIR/lib/$libname"
    if [ ! -f "$dest" ]; then
        echo "  Copying subproject lib: $libname"
        cp "$lib" "$dest"
    fi
done

echo "=== All libs in $SCRATCH/$ARCH_DIR/lib/ ==="
ls -lh "$SCRATCH/$ARCH_DIR/lib/"

# Copy mpv public API headers
MPV_INCLUDE_DIR="$SCRATCH/$ARCH_DIR/include/mpv"
mkdir -p "$MPV_INCLUDE_DIR"
MPV_SRC_DIR="$(ls -d ${SRC}/mpv-* 2>/dev/null | head -1)"
if [ -n "$MPV_SRC_DIR" ]; then
    cp "$MPV_SRC_DIR/libmpv/client.h"    "$MPV_INCLUDE_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/libmpv/render.h"    "$MPV_INCLUDE_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/libmpv/render_gl.h" "$MPV_INCLUDE_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/libmpv/stream_cb.h" "$MPV_INCLUDE_DIR/" 2>/dev/null || true
    echo "mpv public API headers copied to $MPV_INCLUDE_DIR/"
    ls -la "$MPV_INCLUDE_DIR/"
fi

echo "=== Symbol integrity check (Improved) ==="
MPV_LIB="$SCRATCH/$ARCH_DIR/lib/libmpv.a"
if [ -f "$MPV_LIB" ]; then
    nm -gU "$MPV_LIB" | awk '{print $NF}' | sort -u > und_syms.txt
    find "$SCRATCH/$ARCH_DIR/lib" -name "*.a" ! -name "libmpv.a" -print0 | xargs -0 nm -gj | sort -u > def_syms.txt
    MISSING_RAW=$(comm -23 und_syms.txt def_syms.txt)
    REAL_MISSING=$(echo "$MISSING_RAW" | grep -vE '^(_objc|_OBJC|_dispatch|_os_|_CF|_SC|_UI|_NS|_GL|_CV|_CM|_Audio|_fmod|_sin|_cos|_malloc|_free|_memcpy|_strlen|_fprintf|_dlopen|_dlsym)')
    UNDEF_COUNT=$(echo "$REAL_MISSING" | grep -c . || echo "0")

    if [ "$UNDEF_COUNT" -eq 0 ] || [ "$REAL_MISSING" = "" ]; then
        echo "  ✅ Symbol check passed (all non-system symbols resolved)."
    else
        echo "  ❌ $UNDEF_COUNT potential missing symbols detected!"
        echo "$REAL_MISSING" | sed 's/^/      /'
        echo "  (Note: If these are system symbols, add them to the filter list)"
    fi
    rm und_syms.txt def_syms.txt
else
    echo "  ⚠️ libmpv.a not found"
fi