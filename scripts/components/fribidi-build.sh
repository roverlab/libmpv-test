#!/bin/sh
set -e

# 确保 configure 脚本有执行权限
chmod +x $SRC/fribidi*/configure 2>/dev/null || true

$SRC/fribidi*/configure $COMMON_OPTIONS
make install