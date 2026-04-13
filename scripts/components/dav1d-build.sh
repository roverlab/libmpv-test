#!/bin/sh
set -e

# Build dav1d (AV1 software decoder) for iOS
# dav1d uses meson as its build system

cd $SRC/dav1d*

echo "Building dav1d with meson..."
echo "  ARCH=$ARCH"
echo "  ENVIRONMENT=$ENVIRONMENT"
echo "  SDKPATH=$SDKPATH"
echo "  SCRATCH=$SCRATCH"

# 确定架构和目标 Triple
if [ "$ARCH" = "arm64" ]; then
    CPU_FAMILY="aarch64"
    CPU="aarch64"
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

if [ "$ENVIRONMENT" = "simulator" ]; then
    ARCH_DIR="arm64-simulator"
else
    ARCH_DIR="$ARCH"
fi

# 确保输出目录存在
mkdir -p "$SCRATCH/$ARCH_DIR"

# 创建 Cross-file
CROSS_FILE="$SCRATCH/$ARCH_DIR/dav1d-cross-file.txt"

cat > "$CROSS_FILE" << EOF
[binaries]
c = 'clang'
cpp = 'clang++'
ar = 'ar'
strip = 'strip'
pkg-config = 'pkg-config'

[host_machine]
system = 'darwin'
cpu_family = '$CPU_FAMILY'
cpu = '$CPU'
endian = 'little'

[properties]
needs_exe_wrapper = true

[built-in options]
c_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG']
cpp_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG']
c_link_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG']
cpp_link_args = ['-target', '$TARGET_TRIPLE', '-isysroot', '$SDKPATH', '$MIN_VERSION_FLAG']
EOF

echo "Cross-file created at: $CROSS_FILE"

# 清理旧的构建目录
if [ -d "build" ]; then
    rm -rf build
fi

# meson 构建
meson setup build \
    --cross-file "$CROSS_FILE" \
    --buildtype=release \
    --default-library=static \
    -Dprefix="$SCRATCH/$ARCH_DIR" \
    -Denable_tools=false \
    -Denable_tests=false \
    -Denable_examples=false

ninja -C build -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
ninja -C build install

echo "dav1d build complete!"
echo "Installed to: $SCRATCH/$ARCH_DIR"
ls -la "$SCRATCH/$ARCH_DIR/lib/libdav1d.a" 2>/dev/null || echo "WARNING: libdav1d.a not found!"
