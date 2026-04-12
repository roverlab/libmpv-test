#!/bin/sh
set -e

# Extract prefix from COMMON_OPTIONS
PREFIX="${COMMON_OPTIONS%% *}"
PREFIX="${PREFIX##*=}"

LIBPLACEBO_DIR=$(ls -d $SRC/libplacebo-* 2>/dev/null | head -1)

if [ -z "$LIBPLACEBO_DIR" ] || [ ! -d "$LIBPLACEBO_DIR" ]; then
    echo "ERROR: libplacebo source directory not found in $SRC"
    exit 1
fi

echo "Building libplacebo with meson..."
echo "  Source: $LIBPLACEBO_DIR"
echo "  Prefix: $PREFIX"

# Create cross-file for iOS
CROSS_FILE=$(mktemp)
cat > "$CROSS_FILE" << EOF
[binaries]
c = ['$(xcrun -sdk iphoneos --find clang)', '-target', 'arm64-apple-ios13.0', '-isysroot', '$SDKPATH', '-miphoneos-version-min=13.0']
cpp = ['$(xcrun -sdk iphoneos --find clang++)', '-target', 'arm64-apple-ios13.0', '-isysroot', '$SDKPATH', '-miphoneos-version-min=13.0']
ar = '$(xcrun --find ar)'
strip = '$(xcrun --find strip)'
pkg-config = 'pkg-config'

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[built-in options]
prefix = '$PREFIX'
libdir = 'lib'
default_library = 'static'
EOF

meson setup "$LIBPLACEBO_DIR"/build "$LIBPLACEBO_DIR" \
	--cross-file "$CROSS_FILE" \
	-Dopengl=enabled \
	-Dvulkan=disabled \
	-Dd3d11=disabled \
	-Ddemos=false \
	-Dtests=false \
	-Dc_args="$CFLAGS" \
	-Dcpp_args="$CXXFLAGS" \
	-Dc_link_args="$LDFLAGS"

rm -f "$CROSS_FILE"

ninja -C "$LIBPLACEBO_DIR"/build -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
ninja -C "$LIBPLACEBO_DIR"/build install
