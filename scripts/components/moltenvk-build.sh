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
#   Package/Release/MoltenVK/static/MoltenVK.xcframework/ios-arm64/          ← 静态库
#   Package/Release/MoltenVK/dynamic/MoltenVK.xcframework/ios-arm64/MoltenVK.framework/  ← 动态库
#   Package/Release/MoltenVK/include/{MoltenVK,vulkan}/                      ← 头文件
#
# 注意: static xcframework 内可能是 .a 文件（不是 .framework bundle）
#       dynamic xcframework 内是 MoltenVK.framework/

if [ "$ENVIRONMENT" = "simulator" ]; then
    # MoltenVK 不同版本生成的 simulator 切片名称可能不同:
    #   - 旧版: ios-arm64-simulator
    #   - 新版: ios-arm64_x86_64-simulator (同时包含 x86_64)
    XCFRAMEWORK_BASE="Package/Release/MoltenVK/static/MoltenVK.xcframework"
    XCFRAMEWORK_SLICE=""
    for candidate in "ios-arm64-simulator" "ios-arm64_x86_64-simulator"; do
        if [ -d "$XCFRAMEWORK_BASE/$candidate" ]; then
            XCFRAMEWORK_SLICE="$XCFRAMEWORK_BASE/$candidate"
            break
        fi
    done
else
    XCFRAMEWORK_SLICE="Package/Release/MoltenVK/static/MoltenVK.xcframework/ios-arm64"
fi

if [ ! -d "$XCFRAMEWORK_SLICE" ]; then
    echo "ERROR: Static xcframework slice not found (expected simulator slice under Package/Release/MoltenVK/static/MoltenVK.xcframework/)"
    echo "  Package/ contents:"
    find Package -type d -maxdepth 6 2>/dev/null | head -40
    exit 1
fi

echo "Static xcframework slice: $XCFRAMEWORK_SLICE"
echo "  Contents:"
ls -la "$XCFRAMEWORK_SLICE/"

# static xcframework 中查找静态库 (.a 文件)
# 可能直接在 slice 根目录，也可能在 MoltenVK.framework 内部
STATIC_LIB=""
if [ -f "$XCFRAMEWORK_SLICE/libMoltenVK.a" ]; then
    STATIC_LIB="$XCFRAMEWORK_SLICE/libMoltenVK.a"
elif [ -f "$XCFRAMEWORK_SLICE/MoltenVK.framework/MoltenVK" ]; then
    STATIC_LIB="$XCFRAMEWORK_SLICE/MoltenVK.framework/MoltenVK"
elif [ -f "$XCFRAMEWORK_SLICE/MoltenVK.framework/libMoltenVK.a" ]; then
    STATIC_LIB="$XCFRAMEWORK_SLICE/MoltenVK.framework/libMoltenVK.a"
elif [ -f "$XCFRAMEWORK_SLICE/MoltenVK.framework/MoltenVK" ]; then
    STATIC_LIB="$XCFRAMEWORK_SLICE/MoltenVK.framework/MoltenVK"
else
    # 兜底：搜索任意 .a 文件
    FOUND_A=$(find "$XCFRAMEWORK_SLICE" -name "*.a" -type f 2>/dev/null | head -1)
    if [ -n "$FOUND_A" ]; then
        STATIC_LIB="$FOUND_A"
    fi
fi

if [ -z "$STATIC_LIB" ]; then
    echo "ERROR: Static library not found in $XCFRAMEWORK_SLICE"
    echo "  Full contents:"
    find "$XCFRAMEWORK_SLICE" -type f 2>/dev/null
    exit 1
fi

echo "Static library: $STATIC_LIB"
file "$STATIC_LIB"

# 同时定位头文件的 framework 路径（用于取 Headers）
FRAMEWORK_PATH=""
if [ -d "$XCFRAMEWORK_SLICE/MoltenVK.framework" ]; then
    FRAMEWORK_PATH="$XCFRAMEWORK_SLICE/MoltenVK.framework"
elif [ -d "Package/Release/MoltenVK/dynamic/MoltenVK.xcframework/ios-arm64/MoltenVK.framework" ]; then
    FRAMEWORK_PATH="Package/Release/MoltenVK/dynamic/MoltenVK.xcframework/ios-arm64/MoltenVK.framework"
fi

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
