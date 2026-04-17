#!/bin/sh
set -e

# =========================================================================
# 版本定义
# =========================================================================
MPV_VERSION="${MPV_VERSION:-0.41.0}"
LIBPLACEBO_VERSION="${LIBPLACEBO_VERSION:-7.360.1}"
LIBASS_VERSION="${LIBASS_VERSION:-0.17.3}"
FREETYPE_VERSION="${FREETYPE_VERSION:-2.13.2}"
HARFBUZZ_VERSION="${HARFBUZZ_VERSION:-8.4.0}"
FRIBIDI_VERSION="${FRIBIDI_VERSION:-1.0.16}"
LCMS2_VERSION="${LCMS2_VERSION:-2.16}"

# Git URLs
MPV_GIT_URL="https://github.com/mpv-player/mpv.git"
LIBPLACEBO_GIT_URL="https://github.com/haasn/libplacebo.git"
LIBASS_GIT_URL="https://github.com/libass/libass.git"
FREETYPE_GIT_URL="https://github.com/freetype/freetype.git"
HARFBUZZ_GIT_URL="https://github.com/harfbuzz/harfbuzz.git"

# 确保 src 目录存在
mkdir -p "$SRC"

# =========================================================================
# 克隆 mpv 源码
# =========================================================================
MPV_SRC="$SRC/mpv"

echo "=== MPV Source Directory ==="
echo "  SRC=$SRC"
echo "  MPV_SRC=$MPV_SRC"

if [ ! -d "$MPV_SRC" ]; then
    echo "=== Cloning mpv $MPV_VERSION ==="
    git clone --depth 1 --branch "v$MPV_VERSION" "$MPV_GIT_URL" "$MPV_SRC"
else
    echo "=== mpv source already exists at $MPV_SRC ==="
fi

# 验证 mpv 源码目录结构
echo "=== Verifying mpv source structure ==="
if [ -d "$MPV_SRC/include/mpv" ]; then
    echo "  mpv headers found at: $MPV_SRC/include/mpv/"
elif [ -d "$MPV_SRC/libmpv" ]; then
    echo "  mpv headers found at: $MPV_SRC/libmpv/ (legacy structure)"
else
    echo "WARNING: Neither include/mpv/ nor libmpv/ found!"
    echo "Contents of $MPV_SRC:"
    ls -la "$MPV_SRC" 2>/dev/null || echo "  Directory does not exist"
fi

cd "$MPV_SRC"

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
unset PKG_CONFIG_PATH # 防止 macOS 本地 brew 环境污染交叉编译

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
# 3. 准备子项目
# =========================================================================
echo "=== Preparing subprojects ==="
mkdir -p subprojects
cd subprojects

# Helper function to clone a subproject
clone_subproject() {
    local name="$1"
    local url="$2"
    local version="$3"
    local target_dir="$4"
    local extra_flags="$5"

    if [ -z "$target_dir" ]; then
        target_dir="$name"
    fi

    if [ ! -d "$target_dir" ]; then
        echo "Cloning $name $version..."
        git clone --depth 1 --branch "$version" $extra_flags "$url" "$target_dir"
    fi
}

# Helper function to download and extract tarball to $SRC/
download_tarball() {
    local name="$1"
    local url="$2"
    local target_dir="$3"

    if [ ! -d "$SRC/$target_dir" ]; then
        echo "Downloading $name..."
        local tarname="${url##*/}"
        if [ ! -f "$ROOT/downloads/$tarname" ]; then
            curl -f -L -- "$url" > "$ROOT/downloads/$tarname"
        fi
        echo "Extracting $name..."
        tar xvf "$ROOT/downloads/$tarname" -C "$SRC"
        # Find extracted directory and rename to target_dir
        local extracted_dir=$(ls -d "$SRC"/${name}* 2>/dev/null | head -1)
        if [ -n "$extracted_dir" ] && [ "$extracted_dir" != "$SRC/$target_dir" ]; then
            mv "$extracted_dir" "$SRC/$target_dir"
        fi
    fi
}

mkdir -p "$ROOT/downloads"

clone_subproject "libplacebo" "$LIBPLACEBO_GIT_URL" "v$LIBPLACEBO_VERSION" "libplacebo" "--recurse-submodules"
clone_subproject "libass"     "$LIBASS_GIT_URL"     "$LIBASS_VERSION"     "libass"
clone_subproject "freetype"  "$FREETYPE_GIT_URL"    "VER-${FREETYPE_VERSION//./-}" "freetype2"
clone_subproject "harfbuzz"  "$HARFBUZZ_GIT_URL"    "$HARFBUZZ_VERSION"   "harfbuzz"

# lcms2 使用 autotools 单独编译（Little-CMS 没有 meson 支持）
LCMS2_URL="https://github.com/mm2/Little-CMS/releases/download/lcms$LCMS2_VERSION/lcms2-$LCMS2_VERSION.tar.gz"
download_tarball "lcms2" "$LCMS2_URL" "lcms2"

echo "=== Building lcms2 with autotools ==="
cd "$SRC/lcms2"
chmod +x configure 2>/dev/null || true
./configure \
    --host="aarch64-apple-darwin" \
    --prefix="$SCRATCH/$ARCH_DIR" \
    --disable-shared \
    --enable-static \
    CFLAGS="-target $TARGET_TRIPLE $MIN_VERSION_FLAG -isysroot $SDKPATH" \
    LDFLAGS="-target $TARGET_TRIPLE $MIN_VERSION_FLAG -isysroot $SDKPATH"
make -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
make install
cd "$MPV_SRC"

# fribidi 使用 autotools 单独编译（不用 meson subproject，避免 gen.tab 需要构建机器编译器）
FRIBIDI_URL="https://github.com/fribidi/fribidi/releases/download/v$FRIBIDI_VERSION/fribidi-$FRIBIDI_VERSION.tar.xz"
download_tarball "fribidi" "$FRIBIDI_URL" "fribidi"

echo "=== Building fribidi with autotools ==="
cd "$SRC/fribidi"
chmod +x configure 2>/dev/null || true
# 用简单的 host triplet，避免旧 config.sub 不认识 arm64-apple-ios*-simulator
# 实际交叉编译通过 CFLAGS/LDFLAGS 中的 -target 控制
./configure \
    --host="aarch64-apple-darwin" \
    --prefix="$SCRATCH/$ARCH_DIR" \
    --disable-shared \
    --enable-static \
    --disable-bin \
    --disable-docs \
    --disable-tests \
    CFLAGS="-target $TARGET_TRIPLE $MIN_VERSION_FLAG -isysroot $SDKPATH" \
    LDFLAGS="-target $TARGET_TRIPLE $MIN_VERSION_FLAG -isysroot $SDKPATH"
make -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
make install
cd "$MPV_SRC"

# 确保当前目录是 mpv 源码根目录（meson.build 所在位置）
# 注意：此时可能已经在 $MPV_SRC（fribidi 编完后 cd 回来的），
# 也可能在 subprojects/ 下，统一 cd 到 $MPV_SRC 确保正确

# =========================================================================
# 4. 生成 Cross-file
# =========================================================================
CROSS_FILE="$SCRATCH/$ARCH_DIR/mpv-cross-file.txt"

# 确定 subsystem（meson cross-file 需要）
if [ "$ENVIRONMENT" = "simulator" ]; then
    SUBSYSTEM="ios-simulator"
else
    SUBSYSTEM="ios"
fi

# 注意：meson cross-file 中数组元素必须单独列出

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
subsystem = '$SUBSYSTEM'
kernel = 'xnu'
cpu_family = '$CPU_FAMILY'
cpu = '$CPU'
endian = 'little'

[properties]
needs_exe_wrapper = true
has_function_printf = true
pkg_config_path = ['$SCRATCH/$ARCH_DIR/lib/pkgconfig']

[built-in options]
default_library = 'static'
c_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG', '-I$SCRATCH/$ARCH_DIR/include']
cpp_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG', '-I$SCRATCH/$ARCH_DIR/include']
objc_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG', '-I$SCRATCH/$ARCH_DIR/include']
objcpp_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG', '-I$SCRATCH/$ARCH_DIR/include']
c_link_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG', '-lc++']
cpp_link_args = c_link_args
objc_link_args = c_link_args
objcpp_link_args = c_link_args
EOF

echo "Cross-file created at: $CROSS_FILE"

if [ -d "build" ]; then
    echo "Cleaning previous build directory..."
    rm -rf build
fi

# 清除可能影响交叉编译的环境变量
unset SDKROOT CFLAGS CXXFLAGS LDFLAGS CPPFLAGS
export SDKROOT=$(xcrun --sdk macosx --show-sdk-path)

# =========================================================================
# 5. Meson 构建
# =========================================================================
# 定义编译参数数组
ARGS=(
    --cross-file "$CROSS_FILE"
    --buildtype=release
    --wrap-mode=nodownload
    -Ddefault_library=static
    -Dcplayer=false
    -Dgpl=false
    -Dlibmpv=true

    # scripting
    -Dlua=disabled
    -Djavascript=disabled

    # Apple 平台核心 (禁用 videotoolbox-gl/pl，因 ios-gl 在新 SDK 中不兼容)
    -Davfoundation=disabled
    -Dvideotoolbox-pl=disabled
    -Dvideotoolbox-gl=disabled

    # 音频（iOS 必备）
    -Daudiounit=enabled
    -Dcoreaudio=disabled

    -Dgl=enabled
    -Dios-gl=enabled
    -Dplain-gl=enabled
    -Degl=disabled

    # 窗口系统
    -Dcocoa=disabled
    -Dswift-build=disabled
    -Dmacos-cocoa-cb=disabled

    # 平台无关关闭
    -Dx11=disabled
    -Dwayland=disabled
    -Dalsa=disabled

    # 文档
    -Dmanpage-build=disabled
    -Dhtml-build=disabled
    -Dpdf-build=disabled

    # libplacebo (仅 OpenGL, 不使用 vulkan/shaderc)
    -Dlibplacebo:vulkan=disabled
    -Dlibplacebo:opengl=enabled
    -Dlibplacebo:glslang=disabled
    -Dlibplacebo:shaderc=disabled
    -Dlibplacebo:lcms=enabled
    -Dlibplacebo:dovi=disabled
    -Dlibplacebo:libdovi=disabled
    -Dlibplacebo:xxhash=disabled

    # 字符/容器
    -Diconv=enabled
    -Dlibarchive=disabled
    -Duchardet=disabled

    # 颜色管理
    -Dlcms2=enabled

    # 图片
    -Djpeg=disabled

    # 字幕（最小）
    -Dlibass:coretext=enabled
    -Dlibass:fontconfig=disabled
    -Dlibass:asm=disabled
    -Dlibass:directwrite=disabled

    # freetype 精简
    -Dfreetype2:png=disabled
    -Dfreetype2:bzip2=disabled
    -Dfreetype2:brotli=disabled

    # harfbuzz
    -Dharfbuzz:glib=disabled
    -Dharfbuzz:icu=disabled
    -Dharfbuzz:cairo=disabled
    -Dharfbuzz:freetype=enabled

)

# 运行命令
# 先打印调试信息，确认 pkg-config 能找到正确的依赖
echo "=== pkg-config debug info ==="
echo "  PKG_CONFIG_LIBDIR=$PKG_CONFIG_LIBDIR"
echo "  PKG_CONFIG_PATH=${PKG_CONFIG_PATH:-<unset>}"
echo ""
echo "  libplacebo.pc:"
pkg-config --modversion libplacebo 2>&1 || echo "  WARNING: pkg-config cannot find libplacebo!"
echo "  libplacebo cflags:"
pkg-config --cflags libplacebo 2>&1 || true
echo "  libplacebo libs:"
pkg-config --libs libplacebo 2>&1 || true
echo ""
echo "  Working directory: $(pwd)"
echo "  meson.build exists: $(test -f meson.build && echo YES || echo NO)"
echo "============================="

meson setup build "${ARGS[@]}"

# 打印 meson 构建配置中的关键 feature 状态
echo ""
echo "=== Meson Build Configuration ==="
if [ -f "build/meson-info/intro-buildoptions.json" ]; then
    echo "Feature status from meson config:"
    # 使用 python 解析 JSON 来获取关键选项的状态
    python3 -c "
import json
with open('build/meson-info/intro-buildoptions.json') as f:
    opts = json.load(f)
    for opt in opts:
        name = opt.get('name', '')
        if any(x in name for x in ['gl', 'libplacebo', 'ios-gl', 'plain-gl']):
            print(f\"  {name}: {opt.get('value', 'N/A')}\")
" 2>/dev/null || echo "  (could not parse meson config)"
fi

echo ""
echo "=== Meson Targets ==="
if [ -f "build/meson-info/intro-targets.json" ]; then
    python3 -c "
import json
with open('build/meson-info/intro-targets.json') as f:
    targets = json.load(f)
    for t in targets:
        name = t.get('name', '')
        if 'mpv' in name or 'gl' in name:
            print(f\"  Target: {name}\")
" 2>/dev/null || true
fi
echo "============================="

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

# mpv 头文件在 include/mpv/ 目录，不是 libmpv/
echo "=== Copying mpv headers from $MPV_SRC/include/mpv/ ==="
if [ -d "$MPV_SRC/include/mpv" ]; then
    cp "$MPV_SRC/include/mpv/client.h"    "$MPV_INCLUDE_DIR/" 2>/dev/null || echo "Warning: client.h not found"
    cp "$MPV_SRC/include/mpv/render.h"    "$MPV_INCLUDE_DIR/" 2>/dev/null || echo "Warning: render.h not found"
    cp "$MPV_SRC/include/mpv/render_gl.h" "$MPV_INCLUDE_DIR/" 2>/dev/null || echo "Warning: render_gl.h not found"
    cp "$MPV_SRC/include/mpv/stream_cb.h" "$MPV_INCLUDE_DIR/" 2>/dev/null || echo "Warning: stream_cb.h not found"
    echo "=== mpv headers copied ==="
    ls -la "$MPV_INCLUDE_DIR/"
else
    echo "ERROR: $MPV_SRC/include/mpv directory not found!"
    echo "Looking for headers in $MPV_SRC..."
    find "$MPV_SRC" -name "client.h" -type f 2>/dev/null | head -5
fi


echo "Build complete!"

# =========================================================================
# 7. 验证 OpenGL 编译成功
# =========================================================================
echo ""
echo "=== Verifying OpenGL symbols ==="
MPV_LIB="$SCRATCH/$ARCH_DIR/lib/libmpv.a"
if [ -f "$MPV_LIB" ]; then
    echo "Checking for OpenGL render symbols in libmpv.a:"
    nm "$MPV_LIB" 2>/dev/null | grep -i "render_gl" | head -10 || echo "  No render_gl symbols found"
    nm "$MPV_LIB" 2>/dev/null | grep -i "ra_ctx_gl" | head -5 || echo "  No ra_ctx_gl symbols found"
    nm "$MPV_LIB" 2>/dev/null | grep -i "video_out_gl" | head -5 || echo "  No video_out_gl symbols found"
else
    echo "WARNING: libmpv.a not found at $MPV_LIB"
fi

echo ""
echo "Build complete!"
