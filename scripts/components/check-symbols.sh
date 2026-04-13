#!/bin/bash
# =========================================================================
# 符号完整性检查 - 纯链接器测试
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

# 修复2：正确展开通配符获取构建目录
MPV_BUILD_DIR=$(ls -d "$SRC"/mpv*/build 2>/dev/null | head -n 1 || true)

if [ -n "$MPV_BUILD_DIR" ] && [ -d "$MPV_BUILD_DIR" ]; then
    # 修复4：使用 -t commands 获取历史命令，防止 ninja 因为 up-to-date 不输出
    LINK_LINE=$(ninja -C "$MPV_BUILD_DIR" -t commands 2>/dev/null | grep "\.a" | grep -oE '@[^ ]+' | head -1)
    
    if [ -n "$LINK_LINE" ]; then
        RSP_FILE="${LINK_LINE#@}"
        
        # 修复3：处理 rsp 文件的相对路径问题
        if [[ "$RSP_FILE" != /* ]]; then
            RSP_FILE="$MPV_BUILD_DIR/$RSP_FILE"
        fi
        
        if [ -f "$RSP_FILE" ]; then
            EXTRA_LINK_ARGS="@$RSP_FILE"
            echo "  Reusing linker rsp: $RSP_FILE"
        else
            echo "  ⚠️  Rsp file not found: $RSP_FILE, using minimal"
            EXTRA_LINK_ARGS="-framework Foundation -framework CoreFoundation"
        fi
    else
        echo "  ⚠️  No link line in ninja commands, using minimal"
        EXTRA_LINK_ARGS="-framework Foundation -framework CoreFoundation"
    fi
else
    echo "  ⚠️  No build dir found, using minimal"
    EXTRA_LINK_ARGS="-framework Foundation -framework CoreFoundation"
fi

echo "Linking..."
LOG="$TEMP_DIR/link.log"

set +e # 修复1：暂时关闭 set -e，防止由于发生缺失符号导致脚本直接静默崩溃

# shellcheck disable=SC2086
clang -target "$TARGET_TRIPLE" \
     -isysroot "$SDKPATH" $MIN_VERSION_FLAG \
     "$TEMP_DIR/dummy.c" -o "$TEMP_DIR/dummy" \
     $FORCE_LIBS $EXTRA_LINK_ARGS \
     -Wl,-undefined,error \
     > "$LOG" 2>&1

LINK_STATUS=$?
set -e # 恢复 set -e

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