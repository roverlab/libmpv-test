#!/bin/bash
# =========================================================================
# 符号完整性检查 - 纯链接器测试
# =========================================================================
#
# 原则：
#   1. 只做一次真实链接 (-force_load + -undefined,error)
#   2. 不猜测、不分类、不修复
#   3. 输出原始链接器错误
#   4. CI: PASS=exit0, FAIL=exit1+full log
#
# 链接参数来源：ninja -v 抓完整 link line（含 @link.rsp），零解析
# =========================================================================

set -e

if [ -z "$ARCH" ] || [ -z "$SDKPATH" ] || [ -z "$SCRATCH" ]; then
    echo "ERROR: Required env vars not set (ARCH, SDKPATH, SCRATCH)"
    exit 1
fi

if [ "$ENVIRONMENT" = "simulator" ]; then
    ARCH_DIR="arm64-simulator"
    TARGET_TRIPLE="arm64-apple-ios13.0-simulator"
    MIN_VERSION_FLAG="-miphonesimulator-version-min=13.0"
else
    ARCH_DIR="$ARCH"
    TARGET_TRIPLE="arm64-apple-ios13.0"
    MIN_VERSION_FLAG="-miphoneos-version-min=13.0"
fi

LIB_DIR="$SCRATCH/$ARCH_DIR/lib"

echo "=== Symbol check (real linker) ==="
echo "  ARCH=$ARCH ENV=$ENVIRONMENT"

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cat > "$TEMP_DIR/dummy.c" << 'EOF'
int main(void) { return 0; }
EOF

# 收集所有 .a 并 force_load
FORCE_LIBS=""
for lib in \
    "$LIB_DIR/libmpv.a" \
    "$LIB_DIR/libavformat.a" "$LIB_DIR/libavcodec.a" "$LIB_DIR/libavfilter.a" \
    "$LIB_DIR/libswscale.a" "$LIB_DIR/libswresample.a" "$LIB_DIR/libavutil.a" \
    "$LIB_DIR/libass.a" "$LIB_DIR/libfreetype.a" "$LIB_DIR/libharfbuzz.a" \
    "$LIB_DIR/libfribidi.a" "$LIB_DIR/libplacebo.a"; do
    if [ -f "$lib" ]; then
        FORCE_LIBS="$FORCE_LIBS -Wl,-force_load,$lib"
    fi
done

# 从 ninja 构建目录抓取完整的链接命令（含 @link.rsp）
MPV_BUILD_DIR="$SRC/mpv*/build"

if [ -d "$MPV_BUILD_DIR" ]; then
    # ninja -C build -v 输出完整命令行，包含 @link.rsp response file
    # 找到第一个包含 .a 的链接行，直接复用其 @rsp 文件
    LINK_LINE=$(ninja -C "$MPV_BUILD_DIR" -v 2>/dev/null | grep "\.a" | grep -oE '@[^ ]+' | head -1)
    
    if [ -n "$LINK_LINE" ]; then
        # 直接复用 rsp 文件 — 零解析，构建系统给什么就用什么
        RSP_FILE="${LINK_LINE#@}"
        
        if [ -f "$RSP_FILE" ]; then
            EXTRA_LINK_ARGS="@$RSP_FILE"
            echo "  Reusing linker rsp: $RSP_FILE"
        else
            echo "  ⚠️  Rsp file not found: $RSP_FILE, using minimal"
            EXTRA_LINK_ARGS="-framework Foundation -framework CoreFoundation"
        fi
    else
        echo "  ⚠️  No link line in ninja, using minimal"
        EXTRA_LINK_ARGS="-framework Foundation -framework CoreFoundation"
    fi
else
    echo "  ⚠️  No build dir ($MPV_BUILD_DIR), using minimal"
    EXTRA_LINK_ARGS="-framework Foundation -framework CoreFoundation"
fi

echo "Linking..."
LOG="$TEMP_DIR/link.log"

# shellcheck disable=SC2086
clang -target "$TARGET_TRIPLE" \
     -isysroot "$SDKPATH" $MIN_VERSION_FLAG \
     "$TEMP_DIR/dummy.c" -o "$TEMP_DIR/dummy" \
     $FORCE_LIBS $EXTRA_LINK_ARGS \
     -Wl,-undefined,error \
     > "$LOG" 2>&1

if [ $? -eq 0 ]; then
    echo "✅ PASS"
    rm -f "$LOG"
    exit 0
else
    echo "❌ FAIL"
    echo ""
    echo "=== Linker output ==="
    cat "$LOG"
    exit 1
fi
