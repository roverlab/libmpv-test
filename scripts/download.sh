#!/bin/sh

# Change to preferred versions
# Updated versions for compatibility with modern Xcode/Clang
MPV_VERSION="0.39.0"
LIBPLACEBO_VERSION="6.338.2"
FFMPEG_VERSION="7.0"
# Subproject versions (git tags) — built as mpv subprojects via meson
LIBASS_VERSION="0.17.3"
FREETYPE_VERSION="2.13.2"
HARFBUZZ_VERSION="8.4.0"
FRIBIDI_VERSION="1.0.16"
UCHARDET_VERSION="0.0.5"

MPV_URL="https://github.com/mpv-player/mpv/archive/v$MPV_VERSION.tar.gz"
FFMPEG_URL="https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n${FFMPEG_VERSION}.tar.gz"

# Git URLs for subprojects (cloned into mpv/subprojects/)
# These libraries all have meson.build and can be built as meson subprojects
LIBASS_GIT_URL="https://github.com/libass/libass.git"
FREETYPE_GIT_URL="https://github.com/freetype/freetype.git"
HARFBUZZ_GIT_URL="https://github.com/harfbuzz/harfbuzz.git"
FRIBIDI_URL="https://github.com/fribidi/fribidi/releases/download/v$FRIBIDI_VERSION/fribidi-$FRIBIDI_VERSION.tar.xz"
UCHARDET_GIT_URL="https://github.com/BYVoid/uchardet.git"

# libplacebo uses git submodules (glad, jinja, markupsafe, etc.) which are NOT
# included in the tar.gz release. Use git clone --recursive instead.
LIBPLACEBO_GIT_URL="https://github.com/haasn/libplacebo.git"

echo "=== Downloading sources ==="
echo "mpv: $MPV_VERSION"
echo "FFmpeg: $FFMPEG_VERSION"
echo "libplacebo: $LIBPLACEBO_VERSION (git)"
echo "libass: $LIBASS_VERSION (git, as subproject)"
echo "freetype: $FREETYPE_VERSION (git, as subproject)"
echo "harfbuzz: $HARFBUZZ_VERSION (git, as subproject)"
echo "fribidi: $FRIBIDI_VERSION (git, separate build)"
echo "uchardet: $UCHARDET_VERSION (git, as subproject)"
echo ""



rm -rf src
mkdir -p src downloads

# Download tarball-based sources (no submodules needed)
for URL in $FFMPEG_URL $MPV_URL; do
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

# =============================================================================
# Clone subprojects into mpv/subprojects/
# These will be built automatically by meson when building mpv.
# Meson subproject directory name must match the dependency name:
#   libass     → subprojects/libass
#   freetype   → subprojects/freetype2  (mpv's meson.build uses 'freetype2')
#   harfbuzz   → subprojects/harfbuzz
#   fribidi    → subprojects/fribidi
#   uchardet   → subprojects/uchardet
#   libplacebo → subprojects/libplacebo
# =============================================================================
MPV_DIR=$(ls -d src/mpv-* 2>/dev/null | head -1)
if [ -z "$MPV_DIR" ]; then
    echo "ERROR: mpv source directory not found, cannot setup subprojects"
    exit 1
fi

mkdir -p "$MPV_DIR/subprojects"

# Helper function to clone a subproject if not already present
clone_subproject() {
    local name="$1"
    local url="$2"
    local version="$3"
    local target_dir="$4"  # optional: custom directory name inside subprojects/
    local extra_flags="$5" # optional: extra git clone flags

    if [ -z "$target_dir" ]; then
        target_dir="$name"
    fi

    local full_path="$MPV_DIR/subprojects/$target_dir"

    echo ""
    echo ">>> Processing: $name v$version (as mpv subproject: $target_dir)"
    if [ ! -d "$full_path" ]; then
        echo "    Cloning from git..."
        git clone --depth 1 --branch "$version" $extra_flags "$url" "$full_path"
        if [ $? -ne 0 ]; then
            echo "    ERROR: Failed to clone $name"
            exit 1
        fi
        echo "    Cloned successfully into $full_path"
    else
        echo "    Already exists at $full_path, skipping"
    fi
}

# Clone all subprojects
# Note: freetype must be named 'freetype2' because mpv's meson.build looks for
# dependency('freetype2') which maps to subprojects/freetype2
clone_subproject "libplacebo" "$LIBPLACEBO_GIT_URL" "v$LIBPLACEBO_VERSION" "libplacebo" "--recurse-submodules"
clone_subproject "libass"     "$LIBASS_GIT_URL"     "$LIBASS_VERSION"     "libass"
clone_subproject "freetype"  "$FREETYPE_GIT_URL"    "VER-${FREETYPE_VERSION//./-}" "freetype2"
clone_subproject "harfbuzz"  "$HARFBUZZ_GIT_URL"    "$HARFBUZZ_VERSION"   "harfbuzz"
# fribidi 单独下载到 src 目录，使用 tar.xz 压缩包
FRIBIDI_TARNAME="fribidi-$FRIBIDI_VERSION.tar.xz"
echo ""
echo ">>> Processing: $FRIBIDI_TARNAME"
echo "    URL: $FRIBIDI_URL"
if [ ! -f "downloads/$FRIBIDI_TARNAME" ]; then
    echo "    Downloading..."
    curl -f -L -- "$FRIBIDI_URL" > downloads/$FRIBIDI_TARNAME
    if [ $? -ne 0 ]; then
        echo "    ERROR: Failed to download $FRIBIDI_TARNAME"
        exit 1
    fi
    echo "    Downloaded successfully"
else
    echo "    Using cached file"
fi
echo "    Extracting..."
tar xvf downloads/$FRIBIDI_TARNAME -C src
if [ $? -ne 0 ]; then
    echo "    ERROR: Failed to extract $FRIBIDI_TARNAME"
    exit 1
fi
echo "    Done"
clone_subproject "uchardet"  "$UCHARDET_GIT_URL"     "v$UCHARDET_VERSION"   "uchardet"

echo ""
echo "\033[1;32mDownload complete:\033[0m\n mpv: $MPV_VERSION \
                            \n FFmpeg: $FFMPEG_VERSION \
                            \n libplacebo: $LIBPLACEBO_VERSION (subproject) \
                            \n libass: $LIBASS_VERSION (subproject) \
                            \n freetype: $FREETYPE_VERSION (subproject) \
                            \n harfbuzz: $HARFBUZZ_VERSION (subproject) \
                            \n fribidi: $FRIBIDI_VERSION (separate build) \
                            \n uchardet: $UCHARDET_VERSION (subproject)"

echo ""
echo "=== Subprojects in mpv/subprojects/ ==="
ls -la "$MPV_DIR/subprojects/"
