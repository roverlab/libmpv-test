#!/bin/sh
set -e

PREFIX="${COMMON_OPTIONS%% *}"
PREFIX="${PREFIX##*=}"

# Fix CMake compatibility issue with older CMakeLists.txt
UCHARDET_OPTIONS="-DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=false -DCMAKE_OSX_SYSROOT=$SDKPATH -DCMAKE_POLICY_VERSION_MINIMUM=3.5"

cmake -S $SRC/uchardet* -B . $UCHARDET_OPTIONS
make
make install