#!/bin/sh
set -e

cd $SRC/mpv*

echo "Building mpv with meson (Optimized clean environment)..."
echo "  ARCH=$ARCH"
echo "  ENVIRONMENT=$ENVIRONMENT"
echo "  SDKPATH=$SDKPATH"
echo "  SCRATCH=$SCRATCH"

# 1. 基础环境变量校验
if [ -z "$ARCH" ] || [ -z "$SDKPATH" ] || [ -z "$SCRATCH" ]; then
    echo "ERROR: Required environment variables not set"
    exit 1
fi

if [ "$ENVIRONMENT" = "simulator" ]; then
    ARCH_DIR="arm64-simulator"
else
    ARCH_DIR="$ARCH"
fi

export PKG_CONFIG_LIBDIR="$SCRATCH/$ARCH_DIR/lib/pkgconfig"
unset PKG_CONFIG_PATH # 防止 macOS 本地的 brew 环境污染交叉编译

# 2. 确定架构和目标 Triple
if [ "$ARCH" = "arm64" ]; then
    CPU_FAMILY="aarch64"
    CPU="arm64"
    if [ "$ENVIRONMENT" = "simulator" ]; then
        TARGET_TRIPLE="arm64-apple-ios13.0-simulator"
        MIN_VERSION_FLAG="-miphonesimulator-version-min=13.0"
    else
        TARGET_TRIPLE="arm64-apple-ios13.0"
        MIN_VERSION_FLAG="-miphoneos-version-min=13.0"
    fi
else
    echo "ERROR: Unsupported architecture: $ARCH"
    exit 1
fi

mkdir -p "$SCRATCH/$ARCH_DIR"

# =========================================================================
# 3. 准备子项目 (替代极易出错的 wrapdb 自动下载)
# =========================================================================
echo "=== Preparing subprojects ==="
mkdir -p subprojects
cd subprojects

[ ! -d "libplacebo" ] && git clone --depth 1 https://code.videolan.org/videolan/libplacebo.git && (cd libplacebo && git submodule update --init --depth 1)
[ ! -d "libass" ] && git clone --depth 1 https://github.com/libass/libass.git
# fribidi 现在单独编译，不再作为子项目
[ ! -d "harfbuzz" ] && git clone --depth 1 https://github.com/harfbuzz/harfbuzz.git
[ ! -d "freetype2" ] && git clone --depth 1 https://gitlab.freedesktop.org/freetype/freetype.git freetype2
[ ! -d "uchardet" ] && git clone --depth 1 https://gitlab.freedesktop.org/uchardet/uchardet.git

# 返回 mpv 源码根目录（meson.build 在这里）
cd ..

# # 处理 FreeType2 HVF 模块
# cd freetype2
# if [ -f "modules.cfg" ] && ! grep -q "hvf" modules.cfg; then
#     echo "FONT_MODULES += hvf" >> modules.cfg
#     echo "Added HVF module to FreeType2 modules.cfg"
# fi
# cd .. # 退回到 subprojects 目录


# =========================================================================
# 4. 生成 Cross-file
# =========================================================================
CROSS_FILE="$SCRATCH/$ARCH_DIR/mpv-cross-file.txt"

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

if [ -d "build" ]; then
    echo "Cleaning previous build directory..."
    rm -rf build
fi


NATIVE_FILE="$SCRATCH/$ARCH_DIR/native.txt"

cat > "$NATIVE_FILE" << EOF
[binaries]
c = 'cc'
cpp = 'c++'
EOF


unset SDKROOT CFLAGS CXXFLAGS LDFLAGS CPPFLAGS
export SDKROOT=$(xcrun --sdk macosx --show-sdk-path)

# =========================================================================
# 5. Meson 构建
# =========================================================================
meson setup build \
    --cross-file "$CROSS_FILE" \
    --native-file "$NATIVE_FILE" \
    --buildtype=release \
    --wrap-mode=nodownload \
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
    -Diconv=enabled \
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
    -Dharfbuzz:freetype=enabled 

ninja -C build -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
ninja -C build install

# =========================================================================
# 6. 整理产物 (合并静态库与头文件)
# =========================================================================
echo "=== Copying static libs ==="
find "$(pwd)/build" -name "*.a" -type f | while read lib; do
    libname=$(basename "$lib")
    dest="$SCRATCH/$ARCH_DIR/lib/$libname"
    if [ ! -f "$dest" ]; then
        cp "$lib" "$dest"
    fi
done

# Copy libmpv.a specifically to ensure it's there
find "$SCRATCH/$ARCH_DIR" -name "libmpv.a" -exec cp {} "$SCRATCH/$ARCH_DIR/lib/" \; 2>/dev/null || true

# Copy mpv public API headers
MPV_INCLUDE_DIR="$SCRATCH/$ARCH_DIR/include/mpv"
mkdir -p "$MPV_INCLUDE_DIR"
cp libmpv/client.h    "$MPV_INCLUDE_DIR/" 2>/dev/null || true
cp libmpv/render.h    "$MPV_INCLUDE_DIR/" 2>/dev/null || true
cp libmpv/render_gl.h "$MPV_INCLUDE_DIR/" 2>/dev/null || true
cp libmpv/stream_cb.h "$MPV_INCLUDE_DIR/" 2>/dev/null || true

# =========================================================================
# 7. 符号完整性检查
# =========================================================================
echo "=== Symbol integrity check ==="
MPV_LIB="$SCRATCH/$ARCH_DIR/lib/libmpv.a"
if [ -f "$MPV_LIB" ]; then
    nm -gU "$MPV_LIB" | awk '{print $NF}' | sort -u > und_syms.txt
    find "$SCRATCH/$ARCH_DIR/lib" -name "*.a" ! -name "libmpv.a" -print0 | xargs -0 nm -gj | sort -u > def_syms.txt
    MISSING_RAW=$(comm -23 und_syms.txt def_syms.txt)
    REAL_MISSING=$(echo "$MISSING_RAW" | grep -vE '^(_objc|_OBJC|_dispatch|_os_|_CF|_SC|_UI|_NS|_GL|_CV|_CM|_Audio|_fmod|_sin|_cos|_malloc|_free|_memcpy|_strlen|_fprintf|_dlopen|_dlsym|_kCF)')
    UNDEF_COUNT=$(echo "$REAL_MISSING" | grep -c . || echo "0")

    if [ "$UNDEF_COUNT" -eq 0 ] || [ "$REAL_MISSING" = "" ]; then
        echo "  ✅ Symbol check passed (all non-system symbols resolved)."
    else
        echo "  ❌ $UNDEF_COUNT potential missing symbols detected!"
        echo "$REAL_MISSING" | sed 's/^/      /'
    fi
    rm und_syms.txt def_syms.txt
else
    echo "  ⚠️ libmpv.a not found"
fi

echo "Build complete!"