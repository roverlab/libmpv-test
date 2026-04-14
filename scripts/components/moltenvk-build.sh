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

echo "Building MoltenVK..."
./fetchDependencies --ios --iossim
make ios
make iossim

# Locate MoltenVK.xcframework
MOLTENVK_XCFRAMEWORK=""
if [ -d "Package/Latest/MoltenVK/MoltenVK.xcframework" ]; then
    MOLTENVK_XCFRAMEWORK="Package/Latest/MoltenVK/MoltenVK.xcframework"
elif [ -d "Package/Release/MoltenVK/MoltenVK.xcframework" ]; then
    MOLTENVK_XCFRAMEWORK="Package/Release/MoltenVK/MoltenVK.xcframework"
fi

if [ -z "$MOLTENVK_XCFRAMEWORK" ]; then
    echo "ERROR: MoltenVK.xcframework not found after build"
    exit 1
fi

if [ "$ENVIRONMENT" = "simulator" ]; then
    SLICE=$(ls "$MOLTENVK_XCFRAMEWORK" | grep -i simulator | head -1)
else
    SLICE=$(ls "$MOLTENVK_XCFRAMEWORK" | grep -E "^ios-.*arm64" | grep -iv simulator | head -1)
fi

if [ -z "$SLICE" ]; then
    echo "ERROR: Unable to locate matching MoltenVK slice in xcframework"
    exit 1
fi

FRAMEWORK_SRC="$MOLTENVK_XCFRAMEWORK/$SLICE/MoltenVK.framework"
if [ ! -d "$FRAMEWORK_SRC" ]; then
    echo "ERROR: MoltenVK.framework not found in $MOLTENVK_XCFRAMEWORK/$SLICE"
    exit 1
fi

DEST_LIB="$SCRATCH/$ARCH_DIR/lib"
DEST_INCLUDE="$SCRATCH/$ARCH_DIR/include"
DEST_PKGCONFIG="$SCRATCH/$ARCH_DIR/lib/pkgconfig"

mkdir -p "$DEST_LIB" "$DEST_INCLUDE" "$DEST_PKGCONFIG"

rm -rf "$DEST_LIB/MoltenVK.framework"
cp -R "$FRAMEWORK_SRC" "$DEST_LIB/MoltenVK.framework"

rm -rf "$DEST_INCLUDE/MoltenVK"
mkdir -p "$DEST_INCLUDE/MoltenVK"
cp -R "$FRAMEWORK_SRC/Headers/"* "$DEST_INCLUDE/MoltenVK/"

cat > "$DEST_PKGCONFIG/vulkan.pc" << EOF
prefix=$SCRATCH/$ARCH_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: Vulkan
Description: Vulkan (MoltenVK)
Version: 1.0
Libs: -F\${libdir} -framework MoltenVK -framework Metal -framework QuartzCore -framework Foundation -framework CoreGraphics -framework IOSurface
Cflags: -I\${includedir}
EOF

echo "MoltenVK installed to $SCRATCH/$ARCH_DIR"
