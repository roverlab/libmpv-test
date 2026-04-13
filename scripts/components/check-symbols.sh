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
# 框架列表从 mpv cross-file 的 c_link_args 读取，不硬编码
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

# 从 cross-file 提取 c_link_args 中的 framework 和系统库参数
CROSS_FILE="$SCRATCH/$ARCH_DIR/mpv-cross-file.txt"

if [ -f "$CROSS_FILE" ]; then
    # 从 c_link_args 行提取 -framework 和 -l 参数
    # cross-file 格式: c_link_args = ['-target', ..., '-framework', 'Foundation', ...]
    LINK_ARGS=$(grep "^c_link_args" "$CROSS_FILE" | sed "s/^c_link_args = //" | tr -d "'" | tr ',' ' ')
    
    FRAMEWORKS=""
    SYSTEM_LIBS=""
    
    # 解析参数：收集 -framework X 和 -lX
    PREV_ARG=""
    for arg in $LINK_ARGS; do
        if [ "$PREV_ARG" = "-framework" ]; then
            FRAMEWORKS="$FRAMEWORKS -framework $arg"
        elif [ "$PREV_ARG" = "-l" ] || [[ "$arg" == -l* ]]; then
            if [[ "$arg" == -l* ]]; then
                SYSTEM_LIBS="$SYSTEM_LIBS $arg"
            else
                SYSTEM_LIBS="$SYSTEM_LIBS -l$arg"
            fi
        fi
        PREV_ARG="$arg"
    done
    
    echo "  Frameworks from cross-file: $(echo $FRAMEWORKS | wc -w | tr -d ' ') items"
else
    # fallback: 最小基础（仅 Foundation + CoreFoundation）
    echo "  ⚠️  No cross-file found, using minimal frameworks"
    FRAMEWORKS="-framework Foundation -framework CoreFoundation"
    SYSTEM_LIBS=""
fi

echo "Linking..."
LOG="$TEMP_DIR/link.log"

# shellcheck disable=SC2086
clang -target "$TARGET_TRIPLE" \
     -isysroot "$SDKPATH" $MIN_VERSION_FLAG \
     "$TEMP_DIR/dummy.c" -o "$TEMP_DIR/dummy" \
     $FORCE_LIBS $FRAMEWORKS $SYSTEM_LIBS \
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
