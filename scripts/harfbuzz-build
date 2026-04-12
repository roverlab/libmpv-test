#!/bin/sh
set -e

# 确保 configure 脚本有执行权限
chmod +x $SRC/harfbuzz*/configure 2>/dev/null || true

$SRC/harfbuzz*/configure $COMMON_OPTIONS \
							--with-icu=no \
							--with-glib=no \
							--with-fontconfig=no \
							--with-coretext=no \
							--with-freetype=yes \
							--with-cairo=no
make install