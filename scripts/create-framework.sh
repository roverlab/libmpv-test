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

# 查找 mpv 头文件
MPV_SRC_DIR=$(ls -d $ROOT/src/mpv-* 2>/dev/null | head -1)
if [ -z "$MPV_SRC_DIR" ]; then
    echo "ERROR: mpv source directory not found"
    exit 1
fi

# 复制头文件
echo "Copying headers from $MPV_SRC_DIR..."
cp "$MPV_SRC_DIR/libmpv/client.h" "$HEADERS_DIR/"
cp "$MPV_SRC_DIR/video/out/opengl_cb.h" "$HEADERS_DIR/" 2>/dev/null || true
cp "$MPV_SRC_DIR/video/out/gpu/hwdec.h" "$HEADERS_DIR/" 2>/dev/null || true
cp "$MPV_SRC_DIR/render.h" "$HEADERS_DIR/" 2>/dev/null || true
cp "$MPV_SRC_DIR/render_gl.h" "$HEADERS_DIR/" 2>/dev/null || true
cp "$MPV_SRC_DIR/stream_cb.h" "$HEADERS_DIR/" 2>/dev/null || true
cp "$MPV_SRC_DIR/sub/sub.h" "$HEADERS_DIR/" 2>/dev/null || true
cp "$MPV_SRC_DIR/player/scripting/qjs.h" "$HEADERS_DIR/" 2>/dev/null || true

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

# 使用模拟器版本的 libmpv.a (x86_64 用于 CI 测试)
LIBMPV_A="$ROOT/scratch/x86_64/lib/libmpv.a"
if [ ! -f "$LIBMPV_A" ]; then
    # 尝试 arm64 版本
    LIBMPV_A="$ROOT/scratch/arm64/lib/libmpv.a"
fi

if [ ! -f "$LIBMPV_A" ]; then
    echo "ERROR: libmpv.a not found in scratch directories"
    echo "  Tried: $ROOT/scratch/x86_64/lib/libmpv.a"
    echo "  Tried: $ROOT/scratch/arm64/lib/libmpv.a"
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
