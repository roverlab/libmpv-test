#!/bin/sh -e

# Build script for libmpv iOS
#
# Architecture:
#   Step 0 (dav1d):   Build dav1d AV1 decoder separately (must be before ffmpeg)
#   Step 1 (ffmpeg):  Build FFmpeg separately (not a meson subproject)
#   Step shaderc:     Build libshaderc (SPIR-V compiler, used by libplacebo)
#   Step 2 (mpv):     Build mpv + subprojects (libass, freetype, harfbuzz, fribidi,
#                     libplacebo) via meson
#
# dav1d, FFmpeg, and shaderc are built separately before mpv.
# Each component downloads its own source if needed.

# dav1d（单独编译，必须在 ffmpeg 之前）
DAV1D_LIBRARIES="dav1d"
# FFmpeg（单独编译）
FFMPEG_LIBRARIES="ffmpeg"
# libshaderc（单独编译）
SHADERC_LIBRARIES="shaderc"
# libmpv（最后编译，包含其他 subprojects）
MPV_LIBRARIES="libmpv"
# 所有库
ALL_LIBRARIES="$DAV1D_LIBRARIES $FFMPEG_LIBRARIES $SHADERC_LIBRARIES $MPV_LIBRARIES"

export PKG_CONFIG_PATH
export LDFLAGS
export CFLAGS
export CXXFLAGS
export COMMON_OPTIONS
export ENVIRONMENT
export ARCH
export SCRATCH
export SDKPATH


STEP=""
while getopts "e:s:" OPTION; do
case $OPTION in
		e )
			ENVIRONMENT=$(echo "$OPTARG" | awk '{print tolower($0)}')
			;;
		s )
			STEP=$OPTARG
			;;
		? )
			echo "Invalid option"
			exit 1
			;;
	esac
done

# 根据步骤选择要编译的库
case $STEP in
	0|dav1d)
		LIBRARIES="$DAV1D_LIBRARIES"
		echo "=== Step 0: Building dav1d (AV1 decoder) ==="
		;;
	1|ffmpeg)
		LIBRARIES="$FFMPEG_LIBRARIES"
		echo "=== Step 1: Building FFmpeg ==="
		;;
	shaderc)
		LIBRARIES="$SHADERC_LIBRARIES"
		echo "=== Step shaderc: Building libshaderc ==="
		;;
	2|mpv)
		LIBRARIES="$MPV_LIBRARIES"
			echo "=== Step 2: Building libmpv (+ subprojects) ==="
		;;
	"")
		LIBRARIES="$ALL_LIBRARIES"
		echo "=== Building all libraries ==="
		;;
		*)
			echo "Invalid step: $STEP (use 0-2, shaderc, or omit for all)"
	exit 1
		;;
esac

export PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/:$PATH"
DEPLOYMENT_TARGET="13.0"
export IPHONEOS_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"

if [[ "$ENVIRONMENT" = "distribution" ]]; then
    ARCHS="arm64"
elif [[ "$ENVIRONMENT" = "simulator" ]]; then
    ARCHS="arm64"
elif [[ "$ENVIRONMENT" = "" ]]; then
    echo "An environment option is required (-e distribution or -e simulator)"
    exit 1
else
    echo "Unhandled environment option"
    exit 1
fi


ROOT="$(pwd)"
SCRIPTS="$ROOT/scripts"
SCRATCH="$ROOT/scratch"
export ROOT
export SCRIPTS
LIB="$ROOT/lib"
export SRC="$ROOT/src"
mkdir -p $LIB

for ARCH in $ARCHS; do
    # 模拟器环境使用单独的目录
    if [[ "$ENVIRONMENT" = "simulator" ]]; then
        ARCH_DIR="arm64-simulator"
    else
        ARCH_DIR="$ARCH"
    fi
    
    if [[ $ARCH = "arm64" ]]; then
        HOSTFLAG="aarch64"
        # simulator 环境使用模拟器 SDK，否则使用设备 SDK
        if [[ "$ENVIRONMENT" = "simulator" ]]; then
            export SDKPATH="$(xcodebuild -sdk iphonesimulator -version Path)"
            ACFLAGS="-arch $ARCH -isysroot $SDKPATH -mios-simulator-version-min=$DEPLOYMENT_TARGET"
            ALDFLAGS="-arch $ARCH -isysroot $SDKPATH -lbz2"
        else
            export SDKPATH="$(xcodebuild -sdk iphoneos -version Path)"
            ACFLAGS="-arch $ARCH -isysroot $SDKPATH -mios-version-min=$DEPLOYMENT_TARGET"
            ALDFLAGS="-arch $ARCH -isysroot $SDKPATH -lbz2"
        fi
    else
        echo "Unhandled architecture option: $ARCH"
        exit 1
    fi

    if [[ "$ENVIRONMENT" = "simulator" ]]; then
        CFLAGS="$ACFLAGS"
        LDFLAGS="$ALDFLAGS"
    else
        CFLAGS="$ACFLAGS -fembed-bitcode -Os"
        LDFLAGS="$ALDFLAGS -fembed-bitcode -Os"
    fi
    CXXFLAGS="$CFLAGS"

    mkdir -p $SCRATCH

    # 设置 PKG_CONFIG_PATH (only needed for FFmpeg; subprojects use meson)
    PKG_CONFIG_PATH="$SCRATCH/$ARCH_DIR/lib/pkgconfig"
    COMMON_OPTIONS="--prefix=$SCRATCH/$ARCH_DIR --exec-prefix=$SCRATCH/$ARCH_DIR --build=x86_64-apple-darwin14 --enable-static \
                    --disable-shared --disable-dependency-tracking --with-pic --host=$HOSTFLAG"
    
    for LIBRARY in $LIBRARIES; do
        case $LIBRARY in
            "dav1d" )
				$SCRIPTS/components/dav1d-build.sh
				;;
            "ffmpeg" )
				mkdir -p $SCRATCH/$ARCH_DIR/ffmpeg && cd $_ && $SCRIPTS/components/ffmpeg-build.sh
				;;
            "shaderc" )
				$SCRIPTS/components/shaderc-build.sh
				;;
            "libmpv" )
				$SCRIPTS/components/mpv-build.sh
				# ninja install already places libmpv.a in $SCRATCH/$ARCH_DIR/lib/
				# Verify the output file exists
				if [ ! -f "$SCRATCH/$ARCH_DIR/lib/libmpv.a" ]; then
				    echo "ERROR: libmpv.a not found at $SCRATCH/$ARCH_DIR/lib/libmpv.a"
				    echo "Searching for libmpv.a in scratch..."
				    find "$SCRATCH" -name "libmpv.a" 2>/dev/null || true
				    exit 1
				fi
				echo "libmpv.a installed: $SCRATCH/$ARCH_DIR/lib/libmpv.a"
				ls -la "$SCRATCH/$ARCH_DIR/lib/libmpv.a"
				;;
        esac
    done
done
