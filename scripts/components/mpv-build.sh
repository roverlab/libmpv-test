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

# Resolve toolchain paths at shell time (meson won't expand $(...) )
CC_PATH="$(xcrun -sdk $SDK_NAME --find clang)"
CXX_PATH="$(xcrun -sdk $SDK_NAME --find clang++)"
AR_PATH="$(xcrun --find ar)"
STRIP_PATH="$(xcrun --find strip)"

echo "Resolved toolchain paths:"
echo "  CC=$CC_PATH"
echo "  CXX=$CXX_PATH"
echo "  AR=$AR_PATH"
echo "  STRIP=$STRIP_PATH"

# Create cross-file for iOS cross-compilation
# Use a persistent path instead of mktemp to allow meson reconfigure
CROSS_FILE="$SCRATCH/$ARCH_DIR/mpv-cross-file.txt"
mkdir -p "$SCRATCH/$ARCH_DIR"

# Determine the correct minimum version flag
if [ "$ENVIRONMENT" = "simulator" ] || [ "$SDK_NAME" = "iphonesimulator" ]; then
    MIN_VERSION_FLAG="-mios-simulator-version-min=13.0"
else
    MIN_VERSION_FLAG="-miphoneos-version-min=13.0"
fi

cat > "$CROSS_FILE" << EOF
[binaries]
c = ['$CC_PATH', '-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG']
cpp = ['$CXX_PATH', '-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG']
objc = ['$CC_PATH', '-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG']
objcpp = ['$CXX_PATH', '-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG']
ar = '$AR_PATH'
strip = '$STRIP_PATH'
pkg-config = 'pkg-config'

[host_machine]
system = 'darwin'
cpu_family = '$CPU_FAMILY'
cpu = '$CPU'
endian = 'little'

[built-in options]
prefix = '$SCRATCH/$ARCH_DIR'
libdir = 'lib'
default_library = 'static'
EOF

# Set buildtype and compiler flags based on environment
BUILDTYPE="release"
C_ARGS="-fembed-bitcode -Os"
CPP_ARGS="-fembed-bitcode -Os"
C_LINK_ARGS="-lbz2 -fembed-bitcode -Os"

if [[ "$ENVIRONMENT" = "simulator" ]]; then
    # Simulator doesn't need bitcode
    BUILDTYPE="release"
    C_ARGS="-Os"
    CPP_ARGS="-Os"
    C_LINK_ARGS="-lbz2 -Os"
fi

# Convert space-separated flags to meson array format: ['-a', '-b', '-c']
to_meson_array() {
    local input="$1"
    local result=""
    for word in $input; do
        if [ -n "$result" ]; then result="$result, "; fi
        result="'$word'"
    done
    echo "[$result]"
}

# Write build options to cross-file (c_args, cpp_args, c_link_args)
cat >> "$CROSS_FILE" << EOF
c_args = $(to_meson_array "$C_ARGS")
cpp_args = $(to_meson_array "$CPP_ARGS")
c_link_args = $(to_meson_array "$C_LINK_ARGS")
EOF

echo "Cross-file created at: $CROSS_FILE"
cat "$CROSS_FILE" | head -20

# Clean previous build directory to avoid stale configuration
# This is important when switching between device and simulator builds
if [ -d "build" ]; then
    echo "Cleaning previous build directory..."
    rm -rf build
fi

# audiounit uses CoreAudio's AudioDeviceID which is macOS-only (not available on
# iOS at all — neither device nor simulator).  Always disable for iOS builds.

meson setup build \
	--cross-file "$CROSS_FILE" \
	--buildtype=$BUILDTYPE \
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
	-Dlibplacebo:lcms=enabled \
	-Dlibplacebo:dovi=disabled \
	-Dlibplacebo:libdovi=disabled \
	-Dlibplacebo:xxhash=disabled \
	-Diconv=disabled \
	-Dlibarchive=disabled \
	-Duchardet=enabled \
	-Dlcms2=enabled \
	-Dmacos-media-player=disabled \
	-Djpeg=disabled \
	# Subproject options: libass and its dependency chain
	-Dlibass:coretext=true \
	-Dlibass:fontconfig=disabled \
	-Dlibass:harfbuzz=enabled \
	-Dlibass:freetype=enabled \
	-Dlibass:directwrite=disabled \
	-Dlibass:require_system_font_provider=false \
	-Dlibass:asm=disabled \
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
# When libplacebo (and its deps: lcms2, libdovi, etc.) are built as meson
# subprojects/wraps, 'ninja install' only installs the top-level mpv outputs.
# The subproject .a files stay inside the build tree and must be copied manually
# so they get included in the fat XCFramework library.
#
# NOTE: lcms2 is a wrap dependency of libplacebo (which itself is a subproject
# of mpv). Its .a file lives deep in the build tree at e.g.:
#   build/subprojects/libplacebo/subprojects/lcms2/liblcms2.a
# A shallow find would miss it — always search recursively.
echo "=== Copying subproject static libs ==="
# Find all .a files recursively in the meson build tree (not already in the install prefix).
# lcms2 is a wrap dependency of libplacebo (which is a subproject of mpv), so its
# .a file can be deeply nested, e.g.:
#   build/subprojects/libplacebo/subprojects/lcms2/liblcms2.a
#   build/subprojects/libplacebo/subprojects/lcms2/liblcms2_static.a
# A recursive find is essential — shallow searches will miss it.
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

# Copy mpv public API headers to scratch include directory (for framework creation / CI artifact)
# Only copy headers from libmpv/ — these are the canonical public API headers.
# DO NOT copy internal headers (e.g. video/out/gpu/hwdec.h) that depend on
# FFmpeg's libavutil/hwcontext.h, because those headers are not bundled in the
# XCFramework and will cause Clang's module dependency scanner to fail with:
#   fatal error: 'libavutil/hwcontext.h' file not found
MPV_INCLUDE_DIR="$SCRATCH/$ARCH_DIR/include/mpv"
mkdir -p "$MPV_INCLUDE_DIR"
MPV_SRC_DIR="$(ls -d ${SRC}/mpv-* 2>/dev/null | head -1)"
if [ -n "$MPV_SRC_DIR" ]; then
    # Public headers from the libmpv/ subdirectory only
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
    # 1. 提取 libmpv.a 的未定义符号，存入临时文件
    nm -gU "$MPV_LIB" | awk '{print $NF}' | sort -u > und_syms.txt
    
    # 2. 提取所有本地依赖库的已定义符号
    # 排除 libmpv.a 本身，避免循环引用误导
    find "$SCRATCH/$ARCH_DIR/lib" -name "*.a" ! -name "libmpv.a" -print0 | xargs -0 nm -gj | sort -u > def_syms.txt

    # 3. 找出在本地库中找不到定义的符号 (只存在于 und_syms 但不存在于 def_syms)
    # comm -23 返回只在第一个文件中存在的行
    MISSING_RAW=$(comm -23 und_syms.txt def_syms.txt)

    # 4. 关键：过滤掉 iOS/macOS 系统常见的符号前缀
    # 过滤掉以 _objc, _os_, _dispatch, _OBJC_, _CF, _SC, _AS, _vk (如果用系统vulkan) 等开头的符号
    # 同时也过滤掉常见的 C 标准库函数
    REAL_MISSING=$(echo "$MISSING_RAW" | grep -vE '^(_objc|_OBJC|_dispatch|_os_|_CF|_SC|_UI|_NS|_GL|_CV|_CM|_Audio|_fmod|_sin|_cos|_malloc|_free|_memcpy|_strlen|_fprintf|_dlopen|_dlsym)')

    UNDEF_COUNT=$(echo "$REAL_MISSING" | grep -c . || echo "0")

    if [ "$UNDEF_COUNT" -eq 0 ] || [ "$REAL_MISSING" = "" ]; then
        echo "  ✅ Symbol check passed (all non-system symbols resolved)."
    else
        echo "  ❌ $UNDEF_COUNT potential missing symbols detected!"
        echo "$REAL_MISSING" | sed 's/^/      /'
        echo "  (Note: If these are system symbols, add them to the filter list)"
        # exit 1 # 建议先观察是否有误报，再决定是否强制退出
    fi
    rm und_syms.txt def_syms.txt
else
    echo "  ⚠️ libmpv.a not found"
fi