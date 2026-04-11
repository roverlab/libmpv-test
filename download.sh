#!/bin/sh

# Change to preferred versions
# Updated versions for compatibility with modern Xcode/Clang
MPV_VERSION="0.39.0"
LIBPLACEBO_VERSION="6.338.0"
FFMPEG_VERSION="7.0"
LIBASS_VERSION="0.17.3"
FREETYPE_VERSION="2.13.2"
HARFBUZZ_VERSION="8.4.0"
FRIBIDI_VERSION="1.0.16"
UCHARDET_VERSION="0.0.5"

MPV_URL="https://github.com/mpv-player/mpv/archive/v$MPV_VERSION.tar.gz"
FFMPEG_URL="http://www.ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.bz2"
LIBASS_URL="https://github.com/libass/libass/releases/download/$LIBASS_VERSION/libass-$LIBASS_VERSION.tar.gz"
FREETYPE_URL="https://github.com/freetype/freetype/archive/refs/tags/VER-${FREETYPE_VERSION//./-}.tar.gz"
HARFBUZZ_URL="https://github.com/harfbuzz/harfbuzz/releases/download/$HARFBUZZ_VERSION/harfbuzz-$HARFBUZZ_VERSION.tar.xz"
FRIBIDI_URL="https://github.com/fribidi/fribidi/releases/download/v$FRIBIDI_VERSION/fribidi-$FRIBIDI_VERSION.tar.xz"
UCHARDET_URL="https://github.com/BYVoid/uchardet/archive/v$UCHARDET_VERSION.tar.gz"

# libplacebo uses git submodules (glad, jinja, markupsafe, etc.) which are NOT
# included in the tar.gz release. Use git clone --recursive instead.
LIBPLACEBO_GIT_URL="https://github.com/haasn/libplacebo.git"

echo "=== Downloading sources ==="
echo "mpv: $MPV_VERSION"
echo "FFmpeg: $FFMPEG_VERSION"
echo "libass: $LIBASS_VERSION"
echo "freetype: $FREETYPE_VERSION"
echo "harfbuzz: $HARFBUZZ_VERSION"
echo "fribidi: $FRIBIDI_VERSION"
echo "uchardet: $UCHARDET_VERSION"
echo "libplacebo: $LIBPLACEBO_VERSION (git clone with submodules)"
echo ""

rm -rf src
mkdir -p src downloads

# Download tarball-based sources (no submodules needed)
for URL in $UCHARDET_URL $FREETYPE_URL $HARFBUZZ_URL $FRIBIDI_URL $LIBASS_URL $FFMPEG_URL $MPV_URL; do
	TARNAME=${URL##*/}
	echo ""
	echo ">>> Processing: $TARNAME"
	echo "    URL: $URL"
    if [ ! -f "downloads/$TARNAME" ]; then
	    echo "    Downloading..."
	    # Use -k for SourceForge due to SSL certificate issues
	    if echo "$URL" | grep -q "sourceforge.net"; then
	        curl -f -L -k -- $URL > downloads/$TARNAME
	    else
	        curl -f -L -- $URL > downloads/$TARNAME
	    fi
	    if [ $? -ne 0 ]; then
	        echo "    ERROR: Failed to download $TARNAME"
	        exit 1
	    fi
	    echo "    Downloaded successfully"
    else
	    echo "    Using cached file"
    fi
    echo "    Extracting..."
    tar xvf downloads/$TARNAME -C src
    if [ $? -ne 0 ]; then
        echo "    ERROR: Failed to extract $TARNAME"
        exit 1
    fi
    echo "    Done"
done

# libplacebo: use git clone --recursive to get all submodules (glad, jinja, etc.)
echo ""
echo ">>> Processing: libplacebo v$LIBPLACEBO_VERSION"
if [ ! -d "src/libplacebo-${LIBPLACEBO_VERSION}" ]; then
    echo "    Cloning from git (with recursive submodules)..."
    git clone --recurse-submodules --branch "v$LIBPLACEBO_VERSION" "$LIBPLACEBO_GIT_URL" "src/libplacebo-${LIBPLACEBO_VERSION}"
    if [ $? -ne 0 ]; then
        echo "    ERROR: Failed to clone libplacebo"
        exit 1
    fi
    echo "    Cloned successfully with all submodules"
else
    echo "    Already exists, skipping"
fi

echo ""
echo "\033[1;32mDownloaded: \033[0m\n mpv: $MPV_VERSION \
                            \n FFmpeg: $FFMPEG_VERSION \
                            \n libass: $LIBASS_VERSION \
                            \n freetype: $FREETYPE_VERSION \
                            \n harfbuzz: $HARFBUZZ_VERSION \
                            \n fribidi: $FRIBIDI_VERSION \
                            \n uchardet: $UCHARDET_VERSION \
                            \n libplacebo: $LIBPLACEBO_VERSION "
