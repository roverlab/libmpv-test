#!/bin/sh
set -e

if [ -z "$SRC" ] || [ -z "$SCRATCH" ] || [ -z "$ENVIRONMENT" ] || [ -z "$ARCH" ]; then
    echo "ERROR: Required environment variables not set (SRC/SCRATCH/ENVIRONMENT/ARCH)"
    exit 1
fi

if [ "$ENVIRONMENT" = "simulator" ]; then
    ARCH_DIR="arm64-simulator"
else
    ARCH_DIR="$ARCH"
fi

if [ -f "$SCRATCH/$ARCH_DIR/lib/pkgconfig/vulkan.pc" ]; then
    echo "MoltenVK already installed for $ARCH_DIR, skipping"
    exit 0
fi

MOLTENVK_SRC="${MOLTENVK_SRC:-$SRC/MoltenVK}"
MOLTENVK_GIT_URL="${MOLTENVK_GIT_URL:-https://github.com/KhronosGroup/MoltenVK.git}"

if [ ! -d "$MOLTENVK_SRC" ]; then
    echo "Cloning MoltenVK source..."
    git clone --depth 1 "$MOLTENVK_GIT_URL" "$MOLTENVK_SRC"
fi

cd "$MOLTENVK_SRC"

echo "Building MoltenVK for $ENVIRONMENT..."

# 根据目标环境只编译需要的平台
# (CI 中 distribution 和 simulator 本身就是并行 job)
# make ios / make iossim 会同时生成 dynamic 和 static 产物到 Package/ 目录
if [ "$ENVIRONMENT" = "simulator" ]; then
    echo "  Target: iOS Simulator"
    ./fetchDependencies --iossim
    make iossim
else
    echo "  Target: iOS Device"
    ./fetchDependencies --ios
    make ios
fi

# ── 固定路径提取静态库产物 ──
# make ios/iossim 使用 MoltenVKPackaging.xcodeproj 编译，
# 通过 "Package MoltenVK" Build Phase 脚本输出到 Package/Release/MoltenVK/
#
# 已确认的目录结构:
#   Package/Release/MoltenVK/static/MoltenVK.xcframework/ios-arm64/MoltenVK.framework/MoltenVK
#   Package/Release/MoltenVK/dynamic/MoltenVK.xcframework/ios-arm64/MoltenVK.framework/MoltenVK
#   Package/Release/MoltenVK/include/MoltenVK/
#   Package/Release/MoltenVK/include/vulkan/

if [ "$ENVIRONMENT" = "simulator" ]; then
    # iOS Simulator: static xcframework → ios-arm64-simulator slice
    FRAMEWORK_PATH="Package/Release/MoltenVK/static/MoltenVK.xcframework/ios-arm64-simulator/MoltenVK.framework"
else
    # iOS Device: static xcframework → ios-arm64 slice
    FRAMEWORK_PATH="Package/Release/MoltenVK/static/MoltenVK.xcframework/ios-arm64/MoltenVK.framework"
fi

if [ ! -d "$FRAMEWORK_PATH" ]; then
    echo "ERROR: MoltenVK.framework not found at $FRAMEWORK_PATH"
    echo "  Package/ contents:"
    find Package -type d -maxdepth 6 2>/dev/null | head -40
    exit 1
fi

echo "Found MoltenVK.framework at: $FRAMEWORK_PATH"

# 提取静态库文件（framework 内部名为 "MoltenVK"，无扩展名）
STATIC_LIB="$FRAMEWORK_PATH/MoltenVK"
if [ ! -f "$STATIC_LIB" ]; then
    # 备选：有些版本可能叫 libMoltenVK.a
    STATIC_LIB="$FRAMEWORK_PATH/libMoltenVK.a"
fi

if [ ! -f "$STATIC_LIB" ]; then
    echo "ERROR: Static library not found inside framework"
    ls -la "$FRAMEWORK_PATH/"
    exit 1
fi

echo "Static library: $STATIC_LIB"
file "$STATIC_LIB"

DEST_LIB="$SCRATCH/$ARCH_DIR/lib"
DEST_INCLUDE="$SCRATCH/$ARCH_DIR/include"
DEST_PKGCONFIG="$SCRATCH/$ARCH_DIR/lib/pkgconfig"

mkdir -p "$DEST_LIB" "$DEST_INCLUDE" "$DEST_PKGCONFIG"

# 复制静态库为 libMoltenVK.a（统一命名，用于 libtool -static 合并）
cp "$STATIC_LIB" "$DEST_LIB/libMoltenVK.a"
echo "Installed: $DEST_LIB/libMoltenVK.a"
ls -lh "$DEST_LIB/libMoltenVK.a"

# 复制头文件（从 Package/Release/MoltenVK/include/ 取，比 framework Headers 更全）
rm -rf "$DEST_INCLUDE/MoltenVK" "$DEST_INCLUDE/vulkan"
mkdir -p "$DEST_INCLUDE/MoltenVK" "$DEST_INCLUDE/vulkan"
if [ -d "Package/Release/MoltenVK/include/MoltenVK" ]; then
    cp -R Package/Release/MoltenVK/include/MoltenVK/* "$DEST_INCLUDE/MoltenVK/"
fi
if [ -d "Package/Release/MoltenVK/include/vulkan" ]; then
    cp -R Package/Release/MoltenVK/include/vulkan/* "$DEST_INCLUDE/vulkan/"
fi

# 生成 pkg-config 文件（meson 编译 mpv 时通过 pkg-config 查找 vulkan）
cat > "$DEST_PKGCONFIG/vulkan.pc" << EOF
prefix=$SCRATCH/$ARCH_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: Vulkan
Description: Vulkan (MoltenVK) static library
Version: 1.0.3
Libs: -L\${libdir} -lMoltenVK -framework Metal -framework QuartzCore -framework Foundation -framework CoreGraphics -framework IOSurface
Cflags: -I\${includedir}/MoltenVK -I\${includedir}/vulkan
EOF

echo "MoltenVK installed to $SCRATCH/$ARCH_DIR (as libMoltenVK.a static library)"
