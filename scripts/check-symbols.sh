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
# 链接参数来源：ninja -v 抓 @link.rsp（零解析，构建系统给什么用什么）
# 运行位置：build-libmpv job 的 Verify build 步骤（有 build 目录）
# =========================================================================

set -e

if [ -z "$ARCH" ] || [ -z "$SDKPATH" ] || [ -z "$SCRATCH" ] || [ -z "$SRC" ]; then
    echo "ERROR: Required env vars not set (ARCH, SDKPATH, SCRATCH, SRC)"
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
trap 'rm -rf "$TEMP_DIR"' EXIT

cat > "$TEMP_DIR/dummy.c" << 'EOF'
int main(void) { return 0; }
EOF

# 收集所有 .a 并 force_load（强制加载每个 .a 中的所有 .o）
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

echo "  Force-loaded libs: $(echo $FORCE_LIBS | grep -o '\-Wl,-force_load' | wc -l | tr -d ' ') .a files"

# 从 ninja build 目录抓取 @link.rsp（零解析）
MPV_BUILD_DIR=$(ls -d "$SRC"/mpv*/build 2>/dev/null | head -n 1 || true)

if [ -n "$MPV_BUILD_DIR" ] && [ -d "$MPV_BUILD_DIR" ]; then
    # ninja -t commands 输出历史构建命令（不触发重新构建）
    # 找到包含 @link.rsp 的链接行
    LINK_LINE=$(ninja -C "$MPV_BUILD_DIR" -t commands 2>/dev/null | grep -oE '@[^ ]+\.rsp' | head -1)
    
    if [ -n "$LINK_LINE" ]; then
        RSP_FILE="${LINK_LINE#@}"
        
        # 处理相对路径
        if [[ "$RSP_FILE" != /* ]]; then
            RSP_FILE="$MPV_BUILD_DIR/$RSP_FILE"
        fi
        
        if [ -f "$RSP_FILE" ]; then
            EXTRA_LINK_ARGS="@$RSP_FILE"
            echo "  Linker rsp: $RSP_FILE"
        else
            echo "  ⚠️  Rsp file not found: $RSP_FILE"
            EXTRA_LINK_ARGS=""
        fi
    else
        echo "  ⚠️  No link rsp found in ninja commands"
        EXTRA_LINK_ARGS=""
    fi
else
    echo "  ⚠️  No build dir: $MPV_BUILD_DIR"
    EXTRA_LINK_ARGS=""
fi

echo "Linking..."
LOG="$TEMP_DIR/link.log"

# 执行链接（set +e 因为链接失败是预期可能的情况，需要捕获输出）
set +e
# shellcheck disable=SC2086
clang -target "$TARGET_TRIPLE" \
     -isysroot "$SDKPATH" $MIN_VERSION_FLAG \
     "$TEMP_DIR/dummy.c" -o "$TEMP_DIR/dummy" \
     $FORCE_LIBS $EXTRA_LINK_ARGS \
     -Wl,-undefined,error \
     > "$LOG" 2>&1
LINK_STATUS=$?
set -e

if [ $LINK_STATUS -eq 0 ]; then
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
