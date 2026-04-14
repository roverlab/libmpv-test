#!/bin/sh
set -e

# =========================================================================
# libshaderc 构建脚本
# 参考: https://github.com/mpvkit/libshaderc-build
# =========================================================================

SHADERC_VERSION="${SHADERC_VERSION:-v2026.1}"
SHADERC_GIT_URL="https://github.com/google/shaderc"

# 确保目录存在
mkdir -p "$SRC"
mkdir -p "$SCRATCH"

# =========================================================================
# 确定架构和目标
# =========================================================================
if [ -z "$ARCH" ] || [ -z "$SDKPATH" ] || [ -z "$SCRATCH" ]; then
    echo "ERROR: Required environment variables not set"
    exit 1
fi

if [ "$ENVIRONMENT" = "simulator" ]; then
    ARCH_DIR="arm64-simulator"
else
    ARCH_DIR="$ARCH"
fi

# 目标三元组
if [ "$ARCH" = "arm64" ]; then
    CPU_FAMILY="aarch64"
    if [ "$ENVIRONMENT" = "simulator" ]; then
        TARGET_TRIPLE="arm64-apple-ios13.0-simulator"
        MIN_VERSION_FLAG="-miphonesimulator-version-min=13.0"
        CMAKE_SYSTEM_NAME="iOS"
        PLATFORM_NAME="iphonesimulator"
    else
        TARGET_TRIPLE="arm64-apple-ios13.0"
        MIN_VERSION_FLAG="-miphoneos-version-min=13.0"
        CMAKE_SYSTEM_NAME="iOS"
        PLATFORM_NAME="iphoneos"
    fi
else
    echo "ERROR: Unsupported architecture: $ARCH"
    exit 1
fi

# =========================================================================
# 克隆 shaderc 源码
# =========================================================================
SHADERC_SRC="$SRC/shaderc"

if [ ! -d "$SHADERC_SRC" ]; then
    echo "=== Cloning shaderc $SHADERC_VERSION ==="
    git clone --depth 1 --branch "$SHADERC_VERSION" "$SHADERC_GIT_URL" "$SHADERC_SRC"
else
    echo "=== shaderc source already exists at $SHADERC_SRC ==="
fi

cd "$SHADERC_SRC"

# =========================================================================
# 同步依赖 (git-sync-deps)
# =========================================================================
echo "=== Syncing shaderc dependencies ==="
if [ -f "utils/git-sync-deps" ]; then
    python3 utils/git-sync-deps
fi

# =========================================================================
# 修复 spirv-tools 中的 std::system 调用 (iOS 不支持)
# =========================================================================
echo "=== Patching spirv-tools for iOS compatibility ==="

# reduce.cpp
REDUCE_CPP="third_party/spirv-tools/tools/reduce/reduce.cpp"
if [ -f "$REDUCE_CPP" ]; then
    sed -i '' 's/int res = std::system(nullptr);/FILE* fp = popen(nullptr, "r");/g' "$REDUCE_CPP" 2>/dev/null || true
    sed -i '' 's/return res != 0;/return fp == NULL;/g' "$REDUCE_CPP" 2>/dev/null || true
    sed -i '' 's/int status = std::system(command.c_str());/FILE* fp = popen(command.c_str(), "r");/g' "$REDUCE_CPP" 2>/dev/null || true
    sed -i '' 's/return status == 0;/return fp != NULL;/g' "$REDUCE_CPP" 2>/dev/null || true
fi

# fuzz.cpp
FUZZ_CPP="third_party/spirv-tools/tools/fuzz/fuzz.cpp"
if [ -f "$FUZZ_CPP" ]; then
    sed -i '' 's/int res = std::system(nullptr);/FILE* fp = popen(nullptr, "r");/g' "$FUZZ_CPP" 2>/dev/null || true
    sed -i '' 's/return res != 0;/return fp == NULL;/g' "$FUZZ_CPP" 2>/dev/null || true
    sed -i '' 's/int status = std::system(command.c_str());/FILE* fp = popen(command.c_str(), "r");/g' "$FUZZ_CPP" 2>/dev/null || true
    sed -i '' 's/return status == 0;/return fp != NULL;/g' "$FUZZ_CPP" 2>/dev/null || true
fi

# =========================================================================
# CMake 构建
# =========================================================================
BUILD_DIR="$SCRATCH/$ARCH_DIR/shaderc/build"
mkdir -p "$BUILD_DIR"

INSTALL_PREFIX="$SCRATCH/$ARCH_DIR"

echo "=== Building shaderc for $ENVIRONMENT ($ARCH) ==="
echo "  TARGET_TRIPLE=$TARGET_TRIPLE"
echo "  SDKPATH=$SDKPATH"
echo "  INSTALL_PREFIX=$INSTALL_PREFIX"

# 编译标志
C_FLAGS="-target $TARGET_TRIPLE -isysroot $SDKPATH $MIN_VERSION_FLAG -fPIC"
CXX_FLAGS="$C_FLAGS -D_LIBCPP_ENABLE_CXX17_REMOVED_FEATURES"

# CMake 配置
cmake -S "$SHADERC_SRC" -B "$BUILD_DIR" \
    -DCMAKE_VERBOSE_MAKEFILE=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_SYSROOT="$PLATFORM_NAME" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_SYSTEM_NAME="$CMAKE_SYSTEM_NAME" \
    -DCMAKE_SYSTEM_PROCESSOR="$ARCH" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DCMAKE_C_FLAGS="$C_FLAGS" \
    -DCMAKE_CXX_FLAGS="$CXX_FLAGS" \
    -DBUILD_SHARED_LIBS=OFF \
    -DSHADERC_SKIP_TESTS=ON \
    -DSHADERC_SKIP_EXAMPLES=ON \
    -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
    -DENABLE_EXCEPTIONS=ON \
    -DENABLE_GLSLANG_BINARIES=OFF \
    -DSPIRV_SKIP_EXECUTABLES=ON \
    -DSPIRV_TOOLS_BUILD_STATIC=ON \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5

# 编译和安装
cmake --build "$BUILD_DIR" --config Release -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
cmake --install "$BUILD_DIR" --config Release

# =========================================================================
# 创建 pkgconfig 文件
# =========================================================================
PKGCONFIG_DIR="$SCRATCH/$ARCH_DIR/lib/pkgconfig"
mkdir -p "$PKGCONFIG_DIR"

# shaderc_combined.pc (libplacebo 需要这个名称)
cat > "$PKGCONFIG_DIR/shaderc.pc" << EOF
prefix=$INSTALL_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: shaderc
Description: SPIR-V shader compiler (combined)
Version: 2026.1
Libs: -L\${libdir} -lshaderc_combined
Cflags: -I\${includedir}
EOF

echo "=== shaderc build complete ==="
echo "  Libraries:"
ls -la "$SCRATCH/$ARCH_DIR/lib/"*.a 2>/dev/null || true
echo "  Headers:"
ls -la "$SCRATCH/$ARCH_DIR/include/shaderc/" 2>/dev/null || true
echo "  pkgconfig:"
cat "$PKGCONFIG_DIR/shaderc.pc"
