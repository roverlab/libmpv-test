#!/bin/sh
set -e

# Build FFmpeg for iOS

FFMPEG_VERSION="${FFMPEG_VERSION:-8.1}"
FFMPEG_URL="https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n${FFMPEG_VERSION}.tar.gz"

# 确保 src 和 downloads 目录存在
mkdir -p "$SRC" "$ROOT/downloads"

FFMPEG_SRC="$SRC/FFmpeg-n$FFMPEG_VERSION"
FFMPEG_TARNAME="FFmpeg-n$FFMPEG_VERSION.tar.gz"

# 下载源码（如果不存在）
if [ ! -d "$FFMPEG_SRC" ]; then
    echo "=== Downloading FFmpeg $FFMPEG_VERSION ==="
    if [ ! -f "$ROOT/downloads/$FFMPEG_TARNAME" ]; then
        echo "Downloading from $FFMPEG_URL..."
        curl -f -L -- "$FFMPEG_URL" > "$ROOT/downloads/$FFMPEG_TARNAME"
        if [ $? -ne 0 ]; then
            echo "ERROR: Failed to download FFmpeg"
            exit 1
        fi
    fi
    echo "Extracting..."
    tar xvf "$ROOT/downloads/$FFMPEG_TARNAME" -C "$SRC"
fi

# 确保 configure 脚本有执行权限
chmod +x "$FFMPEG_SRC/configure" 2>/dev/null || true

cd "$FFMPEG_SRC"

FFMPEG_OPTIONS="${COMMON_OPTIONS%% *} \
		--enable-cross-compile \
		--disable-lzma \
		--disable-securetransport \
		--disable-sdl2 \
		--disable-debug \
		--disable-programs \
		--disable-doc \
		--enable-pic \
		--enable-static \
		--disable-shared \
		--enable-audiotoolbox \
		--enable-videotoolbox \
		--enable-libdav1d \
		--disable-coreimage \
		--disable-metal"
		# ^ --disable-libjpeg: libjpeg is NOT a system library on iOS.
		# FFmpeg auto-detects the macOS host libjpeg during cross-compile
		# configure and then tries to reference it in the iOS product, causing
		# undefined _jpeg_* symbols at link time.
		# FFmpeg has its own internal MJPEG codec that does not require
		# external libjpeg, so disabling it is safe.

if [[ "$ARCH" = "arm64" ]]; then
	EXPORT="GASPP_FIX_XCODE5=1"
	if [[ "$ENVIRONMENT" = "simulator" ]]; then
		PLATFORM="iPhoneSimulator"
	else
		PLATFORM="iPhoneOS"
	fi
else
	echo "ERROR: Unsupported architecture: $ARCH"
	exit 1
fi

XCRUN_SDK=`echo $PLATFORM | tr '[:upper:]' '[:lower:]'`
CC="xcrun -sdk $XCRUN_SDK clang"

AS="$CC"

./configure $FFMPEG_OPTIONS \
		--target-os=darwin \
		--arch=$ARCH \
		--cc="$CC" \
		--as="$AS" \
		--extra-cflags="$CFLAGS"

make -j4 install $EXPORT
