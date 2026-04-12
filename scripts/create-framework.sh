#!/bin/sh
set -e

# 创建 Libmpv.framework 用于 Xcode 测试
# 将编译好的静态库和头文件打包成 framework

echo "=== Creating Libmpv.framework for testing ==="

ROOT="$(pwd)"
FRAMEWORK_DIR="$ROOT/Tests/lib/Libmpv.framework"
HEADERS_DIR="$FRAMEWORK_DIR/Headers"
MODULES_DIR="$FRAMEWORK_DIR/Modules"

# 清理旧的 framework
rm -rf "$FRAMEWORK_DIR"
mkdir -p "$HEADERS_DIR" "$MODULES_DIR"

# 查找 mpv 头文件（按优先级）
# 1. scratch/arm64/include/mpv/ (编译时复制，CI artifact 中一定存在)
# 2. src/mpv-* (源码解压目录)
# 3. src/mpv (缓存路径)
MPV_INCLUDE_DIR="$ROOT/scratch/arm64/include/mpv"
MPV_SRC_DIR=""

if [ -d "$MPV_INCLUDE_DIR" ]; then
    echo "Found mpv headers in scratch include directory: $MPV_INCLUDE_DIR"
    MPV_SRC_DIR="$MPV_INCLUDE_DIR"
else
    MPV_SRC_DIR=$(ls -d $ROOT/src/mpv-* 2>/dev/null | head -1)
    if [ -z "$MPV_SRC_DIR" ]; then
        MPV_SRC_DIR=$(ls -d $ROOT/src/mpv 2>/dev/null | head -1)
    fi
fi

if [ -z "$MPV_SRC_DIR" ] || [ ! -d "$MPV_SRC_DIR" ]; then
    echo "ERROR: mpv headers not found"
    echo "Checked locations:"
    echo "  1. $MPV_INCLUDE_DIR (scratch include dir)"
    ls -la "$ROOT/scratch/arm64/include/" 2>/dev/null || echo "     (not found)"
    echo "  2. src/mpv-* (source extract dir)"
    ls -la "$ROOT/src/" 2>/dev/null || echo "     (src/ not found)"
    exit 1
fi

echo "Using headers from: $MPV_SRC_DIR"

# 复制头文件
echo "Copying headers from $MPV_SRC_DIR..."
if [ "$MPV_SRC_DIR" = "$MPV_INCLUDE_DIR" ]; then
    # scratch include 目录：头文件直接在此目录下（扁平结构）
    cp "$MPV_SRC_DIR/client.h" "$HEADERS_DIR/"
    cp "$MPV_SRC_DIR/opengl_cb.h" "$HEADERS_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/hwdec.h" "$HEADERS_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/render.h" "$HEADERS_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/render_gl.h" "$HEADERS_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/stream_cb.h" "$HEADERS_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/sub.h" "$HEADERS_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/qjs.h" "$HEADERS_DIR/" 2>/dev/null || true
else
    # 源码目录：头文件在各子目录中
    cp "$MPV_SRC_DIR/libmpv/client.h" "$HEADERS_DIR/"
    cp "$MPV_SRC_DIR/video/out/opengl_cb.h" "$HEADERS_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/video/out/gpu/hwdec.h" "$HEADERS_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/render.h" "$HEADERS_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/render_gl.h" "$HEADERS_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/stream_cb.h" "$HEADERS_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/sub/sub.h" "$HEADERS_DIR/" 2>/dev/null || true
    cp "$MPV_SRC_DIR/player/scripting/qjs.h" "$HEADERS_DIR/" 2>/dev/null || true
fi

# 复制模块映射（用于 Swift import）
echo "Creating module map..."
cat > "$MODULES_DIR/module.modulemap" << 'EOF'
module Libmpv {
    header "client.h"
    header "opengl_cb.h"
    header "hwdec.h"
    header "render.h"
    header "render_gl.h"
    header "stream_cb.h"
    header "sub.h"
    header "qjs.h"
    link "mpv"
    export *
}
EOF

# 使用 arm64 版本的 libmpv.a（distribution 构建）
LIBMPV_A="$ROOT/scratch/arm64/lib/libmpv.a"

if [ ! -f "$LIBMPV_A" ]; then
    echo "ERROR: libmpv.a not found at $LIBMPV_A"
    echo "Contents of scratch directory:"
    ls -laR "$ROOT/scratch/" 2>/dev/null | head -50 || echo "scratch directory not found"
    exit 1
fi

echo "Using libmpv.a from: $LIBMPV_A"

# 创建 framework 中的静态库
cp "$LIBMPV_A" "$FRAMEWORK_DIR/Libmpv"

# 创建 Info.plist
cat > "$FRAMEWORK_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Libmpv</string>
	<key>CFBundleIdentifier</key>
	<string>org.mpv.framework</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Libmpv</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>MinimumOSVersion</key>
	<string>13.0</string>
</dict>
</plist>
EOF

echo "Libmpv.framework created successfully at: $FRAMEWORK_DIR"
ls -la "$FRAMEWORK_DIR/"
