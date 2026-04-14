#!/bin/sh
set -e

# =========================================================================
# 版本定义
# =========================================================================
MPV_VERSION="${MPV_VERSION:-0.41.0}"
LIBPLACEBO_VERSION="${LIBPLACEBO_VERSION:-6.338.2}"
LIBASS_VERSION="${LIBASS_VERSION:-0.17.3}"
FREETYPE_VERSION="${FREETYPE_VERSION:-2.13.2}"
HARFBUZZ_VERSION="${HARFBUZZ_VERSION:-8.4.0}"
FRIBIDI_VERSION="${FRIBIDI_VERSION:-1.0.16}"

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

# 将 Vulkan/MoltenVK 头文件路径添加到编译参数中
# 这对于 meson 的 cc.has_header_symbol() 检测至关重要
# 因为检测时会编译测试程序，需要能找到 vulkan/vulkan_core.h
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

# 添加 moltenvk meson 选项（patch 引用了该选项，需要在 meson.options 中定义）
if ! grep -q "moltenvk" meson.options 2>/dev/null; then
    echo "Adding 'moltenvk' option to meson.options..."
    echo "option('moltenvk', type: 'feature', value: 'auto', description: 'MoltenVK support for Vulkan on macOS/iOS')" >> meson.options
fi

# # 临时修复：替换 meson.build 中 vulkan 版本要求 1.3.238 -> 1.0.0
# # MoltenVK 的 vulkan.pc 报告的版本号无法满足 mpv 的默认检查
# sed -i '' "s/1\.3\.238/1.0.0/" meson.build && echo "Patched: vulkan version 1.3.238 -> 1.0.0"

# # 临时修复：绕过 VK_VERSION_1_3 检测
# # 使用 Python 进行多行替换（更可靠）
# if grep -q "VK_VERSION_1_3" meson.build; then
#     echo "Patching meson.build to bypass VK_VERSION_1_3 check..."
#     python3 << 'PYTHON_EOF'
# import re
# with open('meson.build', 'r') as f:
#     content = f.read()

# # 替换多行的 VK_VERSION_1_3 检测
# pattern = r"features \+= \{'vulkan': vulkan\.found\(\) and \(vulkan\.type_name\(\) == 'internal' or\s+cc\.has_header_symbol\('vulkan/vulkan_core\.h',\s+'VK_VERSION_1_3',\s+dependencies: vulkan\)\)\}"
# replacement = "features += {'vulkan': vulkan.found()}"
# content = re.sub(pattern, replacement, content)

# with open('meson.build', 'w') as f:
#     f.write(content)
# print("Python patch applied")
# PYTHON_EOF
#     echo "Patch applied."
# fi

# =========================================================================
# 修复 libplacebo utils_gen.py 的 Python 3.14 兼容性问题
# Python 3.14 中 ElementTree.__init__() 不再接受 ElementTree 对象
# 需要将 ET.parse(xmlfile) 改为 ET.parse(xmlfile).getroot()
# =========================================================================
UTILS_GEN_PY="subprojects/libplacebo/src/vulkan/utils_gen.py"
if [ -f "$UTILS_GEN_PY" ]; then
    echo "Checking libplacebo utils_gen.py for Python 3.14 compatibility..."
    if grep -q "ET.parse(xmlfile))" "$UTILS_GEN_PY" 2>/dev/null; then
        echo "Patching utils_gen.py for Python 3.14 compatibility..."
        sed -i '' 's/ET.parse(xmlfile))/ET.parse(xmlfile).getroot())/g' "$UTILS_GEN_PY"
        echo "utils_gen.py patched."
    else
        echo "utils_gen.py already compatible or pattern not found."
    fi
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
# 先打印调试信息，确认 pkg-config 能找到正确的依赖
echo "=== pkg-config debug info ==="
echo "  PKG_CONFIG_LIBDIR=$PKG_CONFIG_LIBDIR"
echo "  PKG_CONFIG_PATH=${PKG_CONFIG_PATH:-<unset>}"
echo "  vulkan.pc:"
pkg-config --modversion vulkan 2>&1 || echo "  WARNING: pkg-config cannot find vulkan!"
echo "  vulkan cflags:"
pkg-config --cflags vulkan 2>&1 || true
echo "  vulkan libs:"
pkg-config --libs vulkan 2>&1 || true
echo "  Working directory: $(pwd)"
echo "  meson.build exists: $(test -f meson.build && echo YES || echo NO)"
echo "============================="

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
