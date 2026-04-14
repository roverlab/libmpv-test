#!/bin/sh
set -e

# 确保 configure 脚本有执行权限
chmod +x $SRC/FFmpeg*/configure 2>/dev/null || true

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

if [[ ! `which gas-preprocessor.pl` ]]; then
	# Use montoyo's fork which supports FFmpeg 8+ aarch64 assembly
	# (e.g. VVC ALF neon code with expression indices like v0.h[8 - 8])
	curl -L https://github.com/montoyo/gas-preprocessor/raw/master/gas-preprocessor.pl -o /usr/local/bin/gas-preprocessor.pl \
		&& chmod +x /usr/local/bin/gas-preprocessor.pl
fi

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

if [[ "$ARCH" = "arm64" ]]; then
	AS="gas-preprocessor.pl -arch aarch64 -- $CC"
else
	AS="gas-preprocessor.pl -- $CC"
fi


cd $SRC/FFmpeg* && ./configure $FFMPEG_OPTIONS \
		--target-os=darwin \
		--arch=$ARCH \
		--cc="$CC" \
		--as="$AS" \
		--extra-cflags="$CFLAGS"

make -j4 install $EXPORT
