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
#
# 注意：simulator 默认 make iossim 会编译双架构 (arm64 + x86_64)，
#       但 GitHub Actions runner 是 Apple Silicon (macos-latest)，
#       模拟器只需要 arm64 即可。这里用 xcodebuild 直接指定 ARCHS=arm64
#       来跳过 x86_64，编译时间减少约一半。
if [ "$ENVIRONMENT" = "simulator" ]; then
    echo "  Target: iOS Simulator (arm64 only, skipping x86_64)"
    ./fetchDependencies --iossim
    # 用 xcodebuild 替代 make iossim，显式指定只编 arm64
    # make iossim 内部会调用 xcodebuild 编译 MoltenVKPackaging.xcodeproj 的
    # "MoltenVK Package (iOS only)" scheme，并打包成包含双架构的 xcframework。
    # 我们直接调用 xcodebuild 并设置 ARCHS=arm64 EXCLUDED_ARCHS=x86_64
    # 来只编译 arm64-simulator，跳过 x86_64。
    xcodebuild build \
        -project MoltenVKPackaging.xcodeproj \
        -scheme "MoltenVK Package (iOS only)" \
        -destination 'generic/platform=iOS Simulator' \
        ARCHS=arm64 \
        EXCLUDED_ARCHS=x86_64 \
        GCC_PREPROCESSOR_DEFINITIONS='$${inherited}'
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
    # 单架构 simulator 产物路径 (arm64 only)
    # 使用 xcodebuild ARCHS=arm64 后，生成的切片名为 ios-arm64-simulator
    XCFRAMEWORK_SLICE="Package/Release/MoltenVK/static/MoltenVK.xcframework/ios-arm64-simulator"
    # 兜底：如果找不到单架构版本，尝试双架构版本（兼容旧行为）
    if [ ! -d "$XCFRAMEWORK_SLICE" ]; then
        XCFRAMEWORK_BASE="Package/Release/MoltenVK/static/MoltenVK.xcframework"
        for candidate in "ios-arm64_x86_64-simulator" "ios-arm64-simulator"; do
            if [ -d "$XCFRAMEWORK_BASE/$candidate" ]; then
                XCFRAMEWORK_SLICE="$XCFRAMEWORK_BASE/$candidate"
                break
            fi
        done
    fi
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

# 复制 MoltenVK 特有头文件
rm -rf "$DEST_INCLUDE/MoltenVK" "$DEST_INCLUDE/vulkan"
mkdir -p "$DEST_INCLUDE/MoltenVK" "$DEST_INCLUDE/vulkan"
if [ -d "Package/Release/MoltenVK/include/MoltenVK" ]; then
    cp -R Package/Release/MoltenVK/include/MoltenVK/* "$DEST_INCLUDE/MoltenVK/"
fi

# ── 用 Vulkan-Headers 覆盖 vulkan/ 头文件 ──
# MoltenVK 自带的 vulkan_core.h 可能缺少 VK_VERSION_1_3 等宏定义，
# 导致 meson 的 cc.has_header_symbol() 检测失败。
# 使用标准的 Vulkan-Headers 确保头文件完整。
VULKAN_HEADERS_VERSION="1.3.280"
VULKAN_HEADERS_URL="https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v${VULKAN_HEADERS_VERSION}.tar.gz"
VULKAN_HEADERS_SRC="$SRC/Vulkan-Headers-${VULKAN_HEADERS_VERSION}"

if [ ! -d "$VULKAN_HEADERS_SRC" ]; then
    echo "Downloading Vulkan-Headers v${VULKAN_HEADERS_VERSION}..."
    mkdir -p "$SRC"
    curl -fSL "$VULKAN_HEADERS_URL" -o "$SRC/vulkan-headers.tar.gz"
    tar xzf "$SRC/vulkan-headers.tar.gz" -C "$SRC"
    rm -f "$SRC/vulkan-headers.tar.gz"
fi

if [ -d "$VULKAN_HEADERS_SRC/include/vulkan" ]; then
    echo "Using Vulkan-Headers v${VULKAN_HEADERS_VERSION} for vulkan/ headers"
    cp -R "$VULKAN_HEADERS_SRC/include/vulkan/"* "$DEST_INCLUDE/vulkan/"
    # 同时复制 vk_video/ 目录（包含视频编解码头文件，如 vulkan_video_codec_h264std.h）
    if [ -d "$VULKAN_HEADERS_SRC/include/vk_video" ]; then
        echo "Copying vk_video/ headers..."
        mkdir -p "$DEST_INCLUDE/vk_video"
        cp -R "$VULKAN_HEADERS_SRC/include/vk_video/"* "$DEST_INCLUDE/vk_video/"
    fi
elif [ -d "Package/Release/MoltenVK/include/vulkan" ]; then
    echo "WARNING: Falling back to MoltenVK's bundled vulkan headers (may lack VK_VERSION_1_3)"
    cp -R Package/Release/MoltenVK/include/vulkan/* "$DEST_INCLUDE/vulkan/"
else
    echo "ERROR: No vulkan headers found!"
    exit 1
fi

# 生成 pkg-config 文件（meson 编译 mpv 时通过 pkg-config 查找 vulkan）
#
# 重要：Version 字段必须满足 mpv meson.build 的版本检查要求。
# mpv 0.41.0 要求 vulkan >= 1.3.238（这是 Vulkan Header 版本号，
# 对应 Vulkan API 1.3 + VK_KHR_dynamic_rendering 等特性）。
# MoltenKV 自身版本号（如 1.0.3、1.2.x 等）远低于此要求，
# 但 MoltenVK 实际上已实现 Vulkan 1.3 所需的全部功能，
# 因此这里声明 Vulkan Header 版本号以满足依赖检查。
VULKAN_PC_VERSION="1.3.280"
cat > "$DEST_PKGCONFIG/vulkan.pc" << EOF
prefix=$SCRATCH/$ARCH_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: Vulkan
Description: Vulkan (MoltenVK) static library
Version: $VULKAN_PC_VERSION
Libs: -L\${libdir} -lMoltenVK -framework Metal -framework QuartzCore -framework Foundation -framework CoreGraphics -framework IOSurface
Cflags: -I\${includedir}/MoltenVK -I\${includedir}/vulkan
EOF

echo "MoltenVK installed to $SCRATCH/$ARCH_DIR (as libMoltenVK.a static library)"
