#!/bin/bash

# Build Verification Script for iOS MPV Library
# Verifies all compiled libraries and headers are valid
# Interface: verify-build.sh BUILD_DIR

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [verify-build.sh] $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [verify-build.sh] $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [verify-build.sh] $1"
}

# Validate arguments
if [ $# -ne 1 ]; then
    log_error "Usage: $0 BUILD_DIR"
    log_error "  BUILD_DIR : Root directory containing build outputs"
    exit 1
fi

BUILD_DIR=$1

# Validate build directory
if [ ! -d "$BUILD_DIR" ]; then
    log_error "Build directory does not exist: $BUILD_DIR"
    exit 1
fi

log_info "=========================================="
log_info "Build Verification"
log_info "=========================================="
log_info "Build directory: $BUILD_DIR"

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOGS_DIR="$PROJECT_ROOT/logs"
VERIFICATION_LOG="$LOGS_DIR/verification.log"

# Create logs directory
mkdir -p "$LOGS_DIR"

# Initialize verification log
echo "=========================================" > "$VERIFICATION_LOG"
echo "Build Verification Report" >> "$VERIFICATION_LOG"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')" >> "$VERIFICATION_LOG"
echo "Build Directory: $BUILD_DIR" >> "$VERIFICATION_LOG"
echo "=========================================" >> "$VERIFICATION_LOG"
echo "" >> "$VERIFICATION_LOG"

# Counters for verification results
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Function to record check result
record_check() {
    local check_name=$1
    local result=$2
    local details=$3
    
    ((TOTAL_CHECKS++))
    
    if [ "$result" = "PASS" ]; then
        ((PASSED_CHECKS++))
        echo "[PASS] $check_name" >> "$VERIFICATION_LOG"
        log_info "✓ $check_name"
    else
        ((FAILED_CHECKS++))
        echo "[FAIL] $check_name" >> "$VERIFICATION_LOG"
        echo "       Details: $details" >> "$VERIFICATION_LOG"
        log_error "✗ $check_name"
        log_error "  Details: $details"
    fi
}

# Expected libraries for each dependency
declare -A EXPECTED_LIBS
EXPECTED_LIBS["freetype"]="libfreetype.a"
EXPECTED_LIBS["fribidi"]="libfribidi.a"
EXPECTED_LIBS["uchardet"]="libuchardet.a"
EXPECTED_LIBS["harfbuzz"]="libharfbuzz.a"
EXPECTED_LIBS["libass"]="libass.a"
EXPECTED_LIBS["ffmpeg"]="libavcodec.a libavformat.a libavutil.a libswscale.a libswresample.a"
EXPECTED_LIBS["mpv"]="libmpv.a"

# Expected headers
declare -A EXPECTED_HEADERS
EXPECTED_HEADERS["freetype"]="freetype2/freetype/freetype.h"
EXPECTED_HEADERS["fribidi"]="fribidi/fribidi.h"
EXPECTED_HEADERS["uchardet"]="uchardet/uchardet.h"
EXPECTED_HEADERS["harfbuzz"]="harfbuzz/hb.h"
EXPECTED_HEADERS["libass"]="ass/ass.h"
EXPECTED_HEADERS["ffmpeg"]="libavcodec/avcodec.h libavformat/avformat.h libavutil/avutil.h"
EXPECTED_HEADERS["mpv"]="mpv/client.h"

# Function to verify a library file
verify_library() {
    local target=$1
    local lib_name=$2
    local lib_path="$BUILD_DIR/$target/lib/$lib_name"
    
    # Check file existence
    if [ ! -f "$lib_path" ]; then
        record_check "$target/$lib_name: File existence" "FAIL" "File not found: $lib_path"
        return 1
    fi
    
    record_check "$target/$lib_name: File existence" "PASS" ""
    
    # Check file is not empty
    if [ ! -s "$lib_path" ]; then
        record_check "$target/$lib_name: Non-empty" "FAIL" "File is empty: $lib_path"
        return 1
    fi
    
    record_check "$target/$lib_name: Non-empty" "PASS" ""
    
    # Verify ARM64 architecture using lipo
    if ! lipo -info "$lib_path" | grep -q "arm64"; then
        local arch_info=$(lipo -info "$lib_path" 2>&1)
        record_check "$target/$lib_name: ARM64 architecture" "FAIL" "Expected arm64, found: $arch_info"
        return 1
    fi
    
    record_check "$target/$lib_name: ARM64 architecture" "PASS" ""
    
    return 0
}

# Function to verify a header file
verify_header() {
    local target=$1
    local header_path=$2
    local full_path="$BUILD_DIR/$target/include/$header_path"
    
    # Check file existence
    if [ ! -f "$full_path" ]; then
        record_check "$target/$header_path: Header existence" "FAIL" "Header not found: $full_path"
        return 1
    fi
    
    record_check "$target/$header_path: Header existence" "PASS" ""
    
    # Check file is not empty
    if [ ! -s "$full_path" ]; then
        record_check "$target/$header_path: Header non-empty" "FAIL" "Header is empty: $full_path"
        return 1
    fi
    
    record_check "$target/$header_path: Header non-empty" "PASS" ""
    
    return 0
}

# Function to verify all libraries and headers for a target
verify_target() {
    local target=$1
    
    log_info "Verifying $target target..."
    echo "" >> "$VERIFICATION_LOG"
    echo "Target: $target" >> "$VERIFICATION_LOG"
    echo "----------------------------------------" >> "$VERIFICATION_LOG"
    
    # Check target directory exists
    if [ ! -d "$BUILD_DIR/$target" ]; then
        record_check "$target: Target directory" "FAIL" "Directory not found: $BUILD_DIR/$target"
        return 1
    fi
    
    record_check "$target: Target directory" "PASS" ""
    
    # Check lib directory exists
    if [ ! -d "$BUILD_DIR/$target/lib" ]; then
        record_check "$target: lib directory" "FAIL" "Directory not found: $BUILD_DIR/$target/lib"
        return 1
    fi
    
    record_check "$target: lib directory" "PASS" ""
    
    # Check include directory exists
    if [ ! -d "$BUILD_DIR/$target/include" ]; then
        record_check "$target: include directory" "FAIL" "Directory not found: $BUILD_DIR/$target/include"
        return 1
    fi
    
    record_check "$target: include directory" "PASS" ""
    
    # Verify each dependency's libraries
    for dep in "${!EXPECTED_LIBS[@]}"; do
        local libs="${EXPECTED_LIBS[$dep]}"
        
        for lib in $libs; do
            verify_library "$target" "$lib"
        done
    done
    
    # Verify each dependency's headers
    for dep in "${!EXPECTED_HEADERS[@]}"; do
        local headers="${EXPECTED_HEADERS[$dep]}"
        
        for header in $headers; do
            verify_header "$target" "$header"
        done
    done
    
    return 0
}

# Detect available targets
TARGETS=()

if [ -d "$BUILD_DIR/device" ]; then
    TARGETS+=("device")
fi

if [ -d "$BUILD_DIR/simulator" ]; then
    TARGETS+=("simulator")
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
    log_error "No build targets found in $BUILD_DIR"
    log_error "Expected 'device' and/or 'simulator' directories"
    exit 1
fi

log_info "Found targets: ${TARGETS[*]}"

# Verify each target
for target in "${TARGETS[@]}"; do
    verify_target "$target"
done

# Generate summary
echo "" >> "$VERIFICATION_LOG"
echo "=========================================" >> "$VERIFICATION_LOG"
echo "Verification Summary" >> "$VERIFICATION_LOG"
echo "=========================================" >> "$VERIFICATION_LOG"
echo "Total checks: $TOTAL_CHECKS" >> "$VERIFICATION_LOG"
echo "Passed: $PASSED_CHECKS" >> "$VERIFICATION_LOG"
echo "Failed: $FAILED_CHECKS" >> "$VERIFICATION_LOG"
echo "" >> "$VERIFICATION_LOG"

if [ $FAILED_CHECKS -eq 0 ]; then
    echo "Result: ALL CHECKS PASSED ✓" >> "$VERIFICATION_LOG"
else
    echo "Result: VERIFICATION FAILED ✗" >> "$VERIFICATION_LOG"
fi

echo "=========================================" >> "$VERIFICATION_LOG"

# Print summary
log_info "=========================================="
log_info "Verification Summary"
log_info "=========================================="
log_info "Total checks: $TOTAL_CHECKS"
log_info "Passed: $PASSED_CHECKS"
log_info "Failed: $FAILED_CHECKS"
log_info ""
log_info "Verification report: $VERIFICATION_LOG"

if [ $FAILED_CHECKS -eq 0 ]; then
    log_info "✓ ALL CHECKS PASSED"
    exit 0
else
    log_error "✗ VERIFICATION FAILED"
    log_error "Please review the verification report for details"
    exit 1
fi
