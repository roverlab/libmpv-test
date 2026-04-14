#!/bin/sh
set -e

if [ -z "$SCRIPTS" ]; then
    echo "ERROR: SCRIPTS is not set"
    exit 1
fi

# =========================================================================
# 版本定义
# =========================================================================
MPV_VERSION="${MPV_VERSION:-0.41.0}"
LIBPLACEBO_VERSION="${LIBPLACEBO_VERSION:-6.338.2}"
LIBASS_VERSION="${LIBASS_VERSION:-0.17.3}"
FREETYPE_VERSION="${FREETYPE_VERSION:-2.13.2}"
HARFBUZZ_VERSION="${HARFBUZZ_VERSION:-8.4.0}"
FRIBIDI_VERSION="${FRIBIDI_VERSION:-1.0.16}"

MPV_URL="https://github.com/mpv-player/mpv/archive/v$MPV_VERSION.tar.gz"

# Git URLs for subprojects
LIBPLACEBO_GIT_URL="https://github.com/haasn/libplacebo.git"
LIBASS_GIT_URL="https://github.com/libass/libass.git"
FREETYPE_GIT_URL="https://github.com/freetype/freetype.git"
HARFBUZZ_GIT_URL="https://github.com/harfbuzz/harfbuzz.git"
FRIBIDI_GIT_URL="https://github.com/fribidi/fribidi.git"

# 确保 src 和 downloads 目录存在
mkdir -p "$SRC" "$ROOT/downloads"

# =========================================================================
# 下载 mpv 源码
# =========================================================================
MPV_SRC="$SRC/mpv-$MPV_VERSION"
MPV_TARNAME="mpv-v$MPV_VERSION.tar.gz"

if [ ! -d "$MPV_SRC" ]; then
    echo "=== Downloading mpv $MPV_VERSION ==="
    if [ ! -f "$ROOT/downloads/$MPV_TARNAME" ]; then
        echo "Downloading from $MPV_URL..."
        curl -f -L -- "$MPV_URL" > "$ROOT/downloads/$MPV_TARNAME"
        if [ $? -ne 0 ]; then
            echo "ERROR: Failed to download mpv"
            exit 1
        fi
    fi
    echo "Extracting..."
    tar xvf "$ROOT/downloads/$MPV_TARNAME" -C "$SRC"
fi

# Build MoltenVK (Vulkan on Apple platforms) and install into scratch so mpv can find vulkan.pc
if [ "${ENABLE_MOLTENVK:-1}" = "1" ]; then
    "$SCRIPTS/components/moltenvk-build.sh"
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

clone_subproject "libplacebo" "$LIBPLACEBO_GIT_URL" "v$LIBPLACEBO_VERSION" "libplacebo" "--recurse-submodules"
clone_subproject "libass"     "$LIBASS_GIT_URL"     "$LIBASS_VERSION"     "libass"
clone_subproject "freetype"  "$FREETYPE_GIT_URL"    "VER-${FREETYPE_VERSION//./-}" "freetype2"
clone_subproject "harfbuzz"  "$HARFBUZZ_GIT_URL"    "$HARFBUZZ_VERSION"   "harfbuzz"
clone_subproject "fribidi"   "$FRIBIDI_GIT_URL"     "v$FRIBIDI_VERSION"   "fribidi"

# 返回 mpv 源码根目录（meson.build 在这里）
cd ..

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

[built-in options]
default_library = 'static'
c_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG']
cpp_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG']
objc_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG']
objcpp_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG']
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
# Apply MoltenVK patch (from Thirds/MPVKit) once to enable moltenvk context.
PATCH_FILE="$ROOT/Thirds/MPVKit/Sources/BuildScripts/patch/libmpv/0001-player-add-moltenvk-context.patch"
if [ -f "$PATCH_FILE" ] && ! grep -q "context_moltenvk" meson.build; then
    echo "Applying MoltenVK patch: $PATCH_FILE"
    if command -v git >/dev/null 2>&1; then
        git apply "$PATCH_FILE"
    else
        patch -p1 < "$PATCH_FILE"
    fi
fi

# 添加 moltenvk meson 选项（patch 引用了该选项，需要在 meson_options.txt 中定义）
if ! grep -q "moltenvk" meson_options.txt 2>/dev/null; then
    echo "Adding 'moltenvk' option to meson_options.txt..."
    echo "option('moltenvk', type: 'feature', value: 'auto', description: 'MoltenVK support for Vulkan on macOS/iOS')" >> meson_options.txt
fi


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

    # Apple 平台核心
    -Davfoundation=disabled
    -Dvideotoolbox-pl=enabled
    -Dvideotoolbox-gl=disabled

    # 音频（iOS 必备）
    -Daudiounit=enabled
    -Dcoreaudio=disabled

    # 图形
    -Dgl=enabled
    -Dplain-gl=enabled
    -Dios-gl=enabled
    -Degl=disabled
    -Dvulkan=enabled

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

    # libplacebo
    -Dlibplacebo:vulkan=enabled
    -Dlibplacebo:opengl=disabled
    -Dlibplacebo:glslang=disabled
    -Dlibplacebo:shaderc=disabled
    -Dlibplacebo:lcms=disabled
    -Dlibplacebo:dovi=disabled
    -Dlibplacebo:libdovi=disabled
    -Dlibplacebo:xxhash=disabled

    # 字符/容器
    -Diconv=enabled
    -Dlibarchive=disabled
    -Duchardet=disabled

    # 颜色管理
    -Dlcms2=disabled

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
meson setup build "${ARGS[@]}"

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


echo "Build complete!"
