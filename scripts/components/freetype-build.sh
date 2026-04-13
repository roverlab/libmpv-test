#!/bin/sh
set -e

# freetype 2.13+ requires dlg subproject for autotools build, but the tarball
# doesn't include git submodules. Use CMake instead to avoid this issue entirely.
FREETYPE_DIR=$(ls -d $SRC/freetype-* 2>/dev/null | head -1)

if [ -z "$FREETYPE_DIR" ] || [ ! -d "$FREETYPE_DIR" ]; then
    echo "ERROR: freetype source directory not found in $SRC"
    exit 1
fi

# Extract prefix from COMMON_OPTIONS (same approach as uchardet-build)
PREFIX="${COMMON_OPTIONS%% *}"
PREFIX="${PREFIX##*=}"

echo "Building freetype with CMake..."
echo "  Source: $FREETYPE_DIR"
echo "  Prefix: $PREFIX"

cmake -S "$FREETYPE_DIR" -B . \
	-DCMAKE_INSTALL_PREFIX="$PREFIX" \
	-DCMAKE_SYSTEM_NAME=iOS \
	-DCMAKE_OSX_SYSROOT="$SDKPATH" \
	-DCMAKE_C_FLAGS="$CFLAGS" \
	-DCMAKE_CXX_FLAGS="$CXXFLAGS" \
	-DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
	-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-DBUILD_SHARED_LIBS=OFF \
	-DWITH_ZLIB=ON \
	-DWITH_PNG=OFF \
	-DWITH_BZip2=OFF \
	-DWITH_HarfBuzz=OFF \
	-DCMAKE_DISABLE_FIND_PACKAGE_PNG=TRUE \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5

make -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
make install
