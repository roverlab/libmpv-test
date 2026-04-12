#!/bin/sh -e

# 第1步：字体相关库（容易出错）
FONT_LIBRARIES="libfreetype libharfbuzz libfribidi libass"
# 第2步：其他依赖库（不含 ffmpeg）
OTHER_LIBRARIES="libuchardet"
# 第3步：FFmpeg（可独立缓存）
FFMPEG_LIBRARIES="ffmpeg"
# libplacebo 现在作为 mpv 的 subproject 自动编译，不再需要单独步骤
# 第4步：libmpv（最后编译）
MPV_LIBRARIES="libmpv"
# 所有库（默认）
ALL_LIBRARIES="$FONT_LIBRARIES $OTHER_LIBRARIES"
# LGPL licensed projects should be built as dynamic framework bundles (todo: automate that in this script)
# FRAMEWORKS="libmpv ffmpeg libfribidi"

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

# 所有库（默认）
ALL_LIBRARIES="$FONT_LIBRARIES $OTHER_LIBRARIES $FFMPEG_LIBRARIES $MPV_LIBRARIES"

# 根据步骤选择要编译的库
case $STEP in
	1|font)
		LIBRARIES="$FONT_LIBRARIES"
		echo "=== Step 1: Building font libraries ==="
		;;
	2|other)
		LIBRARIES="$OTHER_LIBRARIES"
		echo "=== Step 2: Building other libraries (uchardet) ==="
		;;
	3|ffmpeg)
		LIBRARIES="$FFMPEG_LIBRARIES"
		echo "=== Step 3: Building FFmpeg ==="
		;;
	4|mpv)
		LIBRARIES="$MPV_LIBRARIES"
		echo "=== Step 5: Building libmpv ==="
		;;
	"")
		LIBRARIES="$ALL_LIBRARIES"
		echo "=== Building all libraries ==="
		;;
		*)
		echo "Invalid step: $STEP (use 1-4 or omit for all)"
		exit 1
		;;
esac

export PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/:$PATH"
DEPLOYMENT_TARGET="11.0"

if [[ "$ENVIRONMENT" = "distribution" ]]; then
    ARCHS="arm64"
elif [[ "$ENVIRONMENT" = "development" ]]; then
    ARCHS="x86_64 arm64"
elif [[ "$ENVIRONMENT" = "simulator" ]]; then
    ARCHS="arm64"
elif [[ "$ENVIRONMENT" = "" ]]; then
    echo "An environment option is required (-e development, -e distribution, or -e simulator)"
    exit 1
else
    echo "Unhandled environment option"
    exit 1
fi


ROOT="$(pwd)"
SCRIPTS="$ROOT/scripts"
# FRAMEWORK="$ROOT/framework"
SCRATCH="$ROOT/scratch"
LIB="$ROOT/lib"
export SRC="$ROOT/src"
mkdir -p $LIB

# 模拟器环境使用单独的目录
if [[ "$ENVIRONMENT" = "simulator" ]]; then
    ARCH_DIR="arm64-simulator"
else
    ARCH_DIR="$ARCH"
fi

for ARCH in $ARCHS; do
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
	elif [[ $ARCH = "x86_64" ]]; then
        HOSTFLAG="x86_64"
		export SDKPATH="$(xcodebuild -sdk iphonesimulator -version Path)"
		ACFLAGS="-arch $ARCH -isysroot $SDKPATH -mios-simulator-version-min=$DEPLOYMENT_TARGET"
		ALDFLAGS="-arch $ARCH -isysroot $SDKPATH -lbz2"
	else
        echo "Unhandled architecture option"
        exit 1
    fi

    if [[ "$ENVIRONMENT" = "development" ]] || [[ "$ENVIRONMENT" = "simulator" ]]; then
        CFLAGS="$ACFLAGS"
        LDFLAGS="$ALDFLAGS"
    else
        CFLAGS="$ACFLAGS -fembed-bitcode -Os"
        LDFLAGS="$ALDFLAGS -fembed-bitcode -Os"
    fi
    CXXFLAGS="$CFLAGS"

    mkdir -p $SCRATCH

    PKG_CONFIG_PATH="$SCRATCH/$ARCH_DIR/lib/pkgconfig"
    COMMON_OPTIONS="--prefix=$SCRATCH/$ARCH_DIR --exec-prefix=$SCRATCH/$ARCH_DIR --build=x86_64-apple-darwin14 --enable-static \
                    --disable-shared --disable-dependency-tracking --with-pic --host=$HOSTFLAG"
    
    for LIBRARY in $LIBRARIES; do
        case $LIBRARY in
            "libfribidi" )
				mkdir -p $SCRATCH/$ARCH_DIR/fribidi && cd $_ && $SCRIPTS/fribidi-build
				;;
            "libfreetype" )
				mkdir -p $SCRATCH/$ARCH_DIR/freetype && cd $_ && $SCRIPTS/freetype-build
			;;
            "libharfbuzz" )
				mkdir -p $SCRATCH/$ARCH_DIR/harfbuzz && cd $_ && $SCRIPTS/harfbuzz-build
				;;
            "libass" )
				mkdir -p $SCRATCH/$ARCH_DIR/libass && cd $_ && $SCRIPTS/libass-build
				;;
            "libuchardet" )
				mkdir -p $SCRATCH/$ARCH_DIR/uchardet && cd $_ && $SCRIPTS/uchardet-build
				;;
            "ffmpeg" )
				mkdir -p $SCRATCH/$ARCH_DIR/ffmpeg && cd $_ && $SCRIPTS/ffmpeg-build
				;;
            "libmpv" )
                if [[ "$ENVIRONMENT" = "development" ]]; then
                    CFLAGS="$ACFLAGS -fembed-bitcode -g2 -Og"
                    LDFLAGS="$ALDFLAGS -fembed-bitcode -g2 -Og"
                fi
				$SCRIPTS/mpv-build
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

if [[ "$ENVIRONMENT" = "development" ]]; then
    for LIBRARY in $LIBRARIES; do
        if [[ "$LIBRARY" != "ffmpeg" ]] && [[ "$LIBRARY" != "libplacebo" ]]; then
            lipo -create $SCRATCH/arm64/lib/$LIBRARY.a $SCRATCH/x86_64/lib/$LIBRARY.a -o $LIB/$LIBRARY.a
        fi
    done
else
    for LIBRARY in $LIBRARIES; do
        if [[ "$LIBRARY" != "ffmpeg" ]] && [[ "$LIBRARY" != "libplacebo" ]]; then
            cp $SCRATCH/arm64/lib/$LIBRARY.a $LIB/$LIBRARY.a
        fi
    done
fi
