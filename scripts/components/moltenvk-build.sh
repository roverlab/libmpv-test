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

# 根据目标环境只编译需要的平台，避免浪费时间编译用不到的版本
# (CI 中 distribution 和 simulator 本身就是并行 job)
if [ "$ENVIRONMENT" = "simulator" ]; then
    echo "  Target: iOS Simulator only"
    ./fetchDependencies --iossim
    make iossim
else
    echo "  Target: iOS Device only"
    ./fetchDependencies --ios
    make ios
fi

# 直接从 Xcode 编译产物中定位 MoltenVK.framework（不需要 xcframework 打包）
# make ios / make iossim 编译后 framework 位于 build/ 目录下
FRAMEWORK_SRC=""
if [ "$ENVIRONMENT" = "simulator" ]; then
    # iOS Simulator 编译产物路径
    for candidate in \
        "build/Release-iphonesimulator/MoltenVK.framework" \
        "build/Debug-iphonesimulator/MoltenVK.framework" \
        "build/Release-iphonesimulator/MoltenVK.xcframework/ios-arm64-simulator/MoltenVK.framework"; do
        if [ -d "$candidate" ]; then
            FRAMEWORK_SRC="$candidate"
            break
        fi
    done
else
    # iOS Device 编译产物路径
    for candidate in \
        "build/Release-iphoneos/MoltenVK.framework" \
        "build/Debug-iphoneos/MoltenVK.framework" \
        "build/Release-iphoneos/MoltenVK.xcframework/ios-arm64/MoltenVK.framework"; do
        if [ -d "$candidate" ]; then
            FRAMEWORK_SRC="$candidate"
            break
        fi
    done
fi

if [ -z "$FRAMEWORK_SRC" ]; then
    echo "ERROR: MoltenVK.framework not found after build"
    echo "Searched in build/ directory:"
    find build -name "MoltenVK.framework" -type d 2>/dev/null || true
    echo "Build output tree:"
    find build -maxdepth 4 -type d 2>/dev/null | head -30 || true
    exit 1
fi

echo "Found MoltenVK.framework at: $FRAMEWORK_SRC"

# MoltenVK.framework 是静态 framework，内部包含静态库 .a 文件
# 提取出来和其他库（dav1d/ffmpeg/libmpv）统一格式，方便后续 libtool -static 合并
# framework 内的静态库文件名可能是 libMoltenVK.a 或 MoltenVK（无扩展名）
STATIC_LIB=""
for lib_candidate in \
    "$FRAMEWORK_SRC/libMoltenVK.a" \
    "$FRAMEWORK_SRC/MoltenVK"; do
    if [ -f "$lib_candidate" ]; then
        # 确认是 Mach-O 静态库
        LIB_TYPE=$(file -b "$lib_candidate" 2>/dev/null | grep -o "static library\|ar archive" || true)
        if [ -n "$LIB_TYPE" ]; then
            STATIC_LIB="$lib_candidate"
            break
        fi
    fi
done

if [ -z "$STATIC_LIB" ]; then
    echo "ERROR: Static library not found inside MoltenVK.framework"
    echo "Framework contents:"
    ls -laR "$FRAMEWORK_SRC/" 2>/dev/null | head -20 || true
    exit 1
fi

echo "Found static library: $STATIC_LIB"
file "$STATIC_LIB"

DEST_LIB="$SCRATCH/$ARCH_DIR/lib"
DEST_INCLUDE="$SCRATCH/$ARCH_DIR/include"
DEST_PKGCONFIG="$SCRATCH/$ARCH_DIR/lib/pkgconfig"

mkdir -p "$DEST_LIB" "$DEST_INCLUDE" "$DEST_PKGCONFIG"

# 复制静态库为 libMoltenVK.a（统一命名）
cp "$STATIC_LIB" "$DEST_LIB/libMoltenVK.a"
echo "Installed static library: $DEST_LIB/libMoltenVK.a"
ls -lh "$DEST_LIB/libMoltenVK.a"

# 复制头文件
rm -rf "$DEST_INCLUDE/MoltenVK"
mkdir -p "$DEST_INCLUDE/MoltenVK"
if [ -d "$FRAMEWORK_SRC/Headers" ]; then
    cp -R "$FRAMEWORK_SRC/Headers/"* "$DEST_INCLUDE/MoltenVK/"
elif [ -d "$FRAMEWORK_SRC/Includes" ]; then
    cp -R "$FRAMEWORK_SRC/Includes/"* "$DEST_INCLUDE/MoltenVK/"
fi

# 生成 pkg-config 文件（指向静态库，用于 meson/pkg-config 查找）
cat > "$DEST_PKGCONFIG/vulkan.pc" << EOF
prefix=$SCRATCH/$ARCH_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: Vulkan
Description: Vulkan (MoltenVK) static library
Version: 1.0
Libs: -L\${libdir} -lMoltenVK -framework Metal -framework QuartzCore -framework Foundation -framework CoreGraphics -framework IOSurface
Cflags: -I\${includedir}/MoltenVK
EOF

echo "MoltenVK installed to $SCRATCH/$ARCH_DIR (as libMoltenKV.a static library)"
