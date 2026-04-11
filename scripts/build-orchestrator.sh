#!/bin/bash

# Build Orchestrator Script for iOS MPV Library
# Coordinates all build steps for MPV and its dependencies
# Interface: build-orchestrator.sh [OPTIONS]

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [orchestrator] $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [orchestrator] $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [orchestrator] $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [orchestrator] $1"
}

# Default configuration
CLEAN_BUILD=false
TARGET="all"
INCREMENTAL=false
VERBOSE=false

# Parse command-line options
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --clean          Clean all previous build artifacts before building"
    echo "  --target TARGET  Build for specific target (device|simulator|all)"
    echo "                   Default: all"
    echo "  --incremental    Enable incremental build (skip unchanged dependencies)"
    echo "  --verbose        Enable verbose logging"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --clean --target all"
    echo "  $0 --target device --incremental"
    echo "  $0 --verbose"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --target)
            TARGET="$2"
            shift 2
            ;;
        --incremental)
            INCREMENTAL=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate target
if [ "$TARGET" != "device" ] && [ "$TARGET" != "simulator" ] && [ "$TARGET" != "all" ]; then
    log_error "Invalid target: $TARGET (must be 'device', 'simulator', or 'all')"
    exit 1
fi

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
export MIN_IOS_VERSION="${MIN_IOS_VERSION:-12.0}"
BUILD_DIR="$PROJECT_ROOT/build"
LOGS_DIR="$PROJECT_ROOT/logs"
CACHE_DIR="$PROJECT_ROOT/cache"
TIMESTAMP_CACHE="$CACHE_DIR/timestamps.cache"

# Create directories
mkdir -p "$LOGS_DIR"
mkdir -p "$CACHE_DIR"

# Main log file
MAIN_LOG="$LOGS_DIR/build-orchestrator.log"

# Redirect output to log file if verbose is disabled
if [ "$VERBOSE" = false ]; then
    exec > >(tee -a "$MAIN_LOG")
    exec 2>&1
fi

log_info "=========================================="
log_info "iOS MPV Library Build Orchestrator"
log_info "=========================================="
log_info "Configuration:"
log_info "  Target: $TARGET"
log_info "  Clean build: $CLEAN_BUILD"
log_info "  Incremental: $INCREMENTAL"
log_info "  Verbose: $VERBOSE"
log_info "  Min iOS version: $MIN_IOS_VERSION"
log_info "  Project root: $PROJECT_ROOT"
log_info "  Logs directory: $LOGS_DIR"

# Clean build artifacts if requested
if [ "$CLEAN_BUILD" = true ]; then
    log_step "Cleaning build artifacts..."
    
    if [ -d "$BUILD_DIR" ]; then
        log_info "Removing build directory: $BUILD_DIR"
        rm -rf "$BUILD_DIR"
    fi
    
    if [ -d "$LOGS_DIR" ]; then
        log_info "Removing logs directory: $LOGS_DIR"
        rm -rf "$LOGS_DIR"
        mkdir -p "$LOGS_DIR"
    fi
    
    if [ -d "$CACHE_DIR" ]; then
        log_info "Removing cache directory: $CACHE_DIR"
        rm -rf "$CACHE_DIR"
        mkdir -p "$CACHE_DIR"
    fi
    
    log_info "✓ Clean completed"
fi

# Detect Xcode and SDK paths
log_step "Detecting Xcode and SDK paths..."

if ! command -v xcode-select &> /dev/null; then
    log_error "xcode-select not found. Please install Xcode Command Line Tools"
    exit 1
fi

XCODE_PATH=$(xcode-select -p)
log_info "Xcode path: $XCODE_PATH"

IOS_DEVICE_SDK="$XCODE_PATH/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
IOS_SIMULATOR_SDK="$XCODE_PATH/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"

if [ ! -d "$IOS_DEVICE_SDK" ]; then
    log_error "iOS device SDK not found at: $IOS_DEVICE_SDK"
    exit 1
fi

if [ ! -d "$IOS_SIMULATOR_SDK" ]; then
    log_error "iOS simulator SDK not found at: $IOS_SIMULATOR_SDK"
    exit 1
fi

log_info "✓ iOS device SDK: $IOS_DEVICE_SDK"
log_info "✓ iOS simulator SDK: $IOS_SIMULATOR_SDK"

# Timestamp tracking functions for incremental builds
get_source_timestamp() {
    local dep=$1
    local build_script="$SCRIPT_DIR/build-$dep.sh"
    
    # Get the latest modification time of the build script
    if [ -f "$build_script" ]; then
        stat -f %m "$build_script" 2>/dev/null || stat -c %Y "$build_script" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

get_cached_timestamp() {
    local dep=$1
    local target=$2
    local cache_key="${dep}_${target}"
    
    if [ -f "$TIMESTAMP_CACHE" ]; then
        grep "^${cache_key}=" "$TIMESTAMP_CACHE" | cut -d'=' -f2 || echo "0"
    else
        echo "0"
    fi
}

update_cached_timestamp() {
    local dep=$1
    local target=$2
    local timestamp=$3
    local cache_key="${dep}_${target}"
    
    # Create cache file if it doesn't exist
    touch "$TIMESTAMP_CACHE"
    
    # Remove old entry if exists
    if grep -q "^${cache_key}=" "$TIMESTAMP_CACHE" 2>/dev/null; then
        sed -i.bak "/^${cache_key}=/d" "$TIMESTAMP_CACHE"
        rm -f "${TIMESTAMP_CACHE}.bak"
    fi
    
    # Add new entry
    echo "${cache_key}=${timestamp}" >> "$TIMESTAMP_CACHE"
}

should_rebuild() {
    local dep=$1
    local target=$2
    
    # If not incremental mode, always rebuild
    if [ "$INCREMENTAL" = false ]; then
        return 0  # true - should rebuild
    fi
    
    # Check if library exists
    local lib_file="$BUILD_DIR/$target/lib/lib$dep.a"
    
    # Special case for FFmpeg (has multiple libraries)
    if [ "$dep" = "ffmpeg" ]; then
        lib_file="$BUILD_DIR/$target/lib/libavcodec.a"
    fi
    
    if [ ! -f "$lib_file" ]; then
        return 0  # true - library doesn't exist, must rebuild
    fi
    
    # Get timestamps
    local source_timestamp=$(get_source_timestamp "$dep")
    local cached_timestamp=$(get_cached_timestamp "$dep" "$target")
    
    # Compare timestamps
    if [ "$source_timestamp" -gt "$cached_timestamp" ]; then
        return 0  # true - source is newer, should rebuild
    else
        return 1  # false - source unchanged, skip rebuild
    fi
}

# Dependency build order
DEPENDENCIES=(
    "freetype"
    "fribidi"
    "uchardet"
    "harfbuzz"
    "libass"
    "ffmpeg"
)

# Function to build a dependency for a specific target
build_dependency() {
    local dep=$1
    local target=$2
    local arch="arm64"
    local sdk_path=""
    
    if [ "$target" = "device" ]; then
        sdk_path="$IOS_DEVICE_SDK"
    else
        sdk_path="$IOS_SIMULATOR_SDK"
    fi
    
    local build_script="$SCRIPT_DIR/build-$dep.sh"
    local log_file="$LOGS_DIR/build-$dep-$target.log"
    
    log_step "Building $dep for $target..."
    
    # Check if build script exists
    if [ ! -f "$build_script" ]; then
        log_error "Build script not found: $build_script"
        return 1
    fi
    
    # Check if rebuild is needed (incremental build logic with timestamp tracking)
    if ! should_rebuild "$dep" "$target"; then
        log_info "✓ $dep unchanged for $target (incremental mode), skipping"
        return 0
    fi
    
    # Execute build script
    local start_time=$(date +%s)
    
    if bash "$build_script" "$target" "$arch" "$sdk_path" > "$log_file" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        # Update timestamp cache on successful build
        local source_timestamp=$(get_source_timestamp "$dep")
        update_cached_timestamp "$dep" "$target" "$source_timestamp"
        
        log_info "✓ $dep build completed for $target (${duration}s)"
        return 0
    else
        log_error "✗ $dep build failed for $target"
        log_error "See log file: $log_file"
        log_error "Last 20 lines of log:"
        tail -n 20 "$log_file"
        return 1
    fi
}

# Function to build MPV for a specific target
build_mpv() {
    local target=$1
    local arch="arm64"
    local sdk_path=""
    local deps_path="$BUILD_DIR/$target"
    
    if [ "$target" = "device" ]; then
        sdk_path="$IOS_DEVICE_SDK"
    else
        sdk_path="$IOS_SIMULATOR_SDK"
    fi
    
    local build_script="$SCRIPT_DIR/build-mpv.sh"
    local log_file="$LOGS_DIR/build-mpv-$target.log"
    
    log_step "Building MPV for $target..."
    
    # Check if build script exists
    if [ ! -f "$build_script" ]; then
        log_error "Build script not found: $build_script"
        return 1
    fi
    
    # Check if rebuild is needed (incremental build logic with timestamp tracking)
    if ! should_rebuild "mpv" "$target"; then
        log_info "✓ MPV unchanged for $target (incremental mode), skipping"
        return 0
    fi
    
    # Execute build script
    local start_time=$(date +%s)
    
    if bash "$build_script" "$target" "$arch" "$sdk_path" "$deps_path" > "$log_file" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        # Update timestamp cache on successful build
        local source_timestamp=$(get_source_timestamp "mpv")
        update_cached_timestamp "mpv" "$target" "$source_timestamp"
        
        log_info "✓ MPV build completed for $target (${duration}s)"
        return 0
    else
        log_error "✗ MPV build failed for $target"
        log_error "See log file: $log_file"
        log_error "Last 20 lines of log:"
        tail -n 20 "$log_file"
        return 1
    fi
}

# Function to build all dependencies and MPV for a target
build_target() {
    local target=$1
    
    log_info "=========================================="
    log_info "Building for target: $target"
    log_info "=========================================="
    
    local target_start_time=$(date +%s)
    
    # Build dependencies in order
    for dep in "${DEPENDENCIES[@]}"; do
        if ! build_dependency "$dep" "$target"; then
            log_error "Failed to build $dep for $target"
            return 1
        fi
    done
    
    # Build MPV
    if ! build_mpv "$target"; then
        log_error "Failed to build MPV for $target"
        return 1
    fi
    
    local target_end_time=$(date +%s)
    local target_duration=$((target_end_time - target_start_time))
    
    log_info "=========================================="
    log_info "✓ Target $target completed successfully (${target_duration}s)"
    log_info "=========================================="
    
    return 0
}

# Main build execution
BUILD_START_TIME=$(date +%s)
BUILD_SUCCESS=true

if [ "$TARGET" = "all" ]; then
    # Build for both device and simulator
    if ! build_target "device"; then
        BUILD_SUCCESS=false
    fi
    
    if ! build_target "simulator"; then
        BUILD_SUCCESS=false
    fi
elif [ "$TARGET" = "device" ] || [ "$TARGET" = "simulator" ]; then
    # Build for specific target
    if ! build_target "$TARGET"; then
        BUILD_SUCCESS=false
    fi
fi

BUILD_END_TIME=$(date +%s)
BUILD_DURATION=$((BUILD_END_TIME - BUILD_START_TIME))

# Summary
log_info "=========================================="
log_info "Build Orchestrator Summary"
log_info "=========================================="
log_info "Total build time: ${BUILD_DURATION}s"
log_info "Logs directory: $LOGS_DIR"

if [ "$BUILD_SUCCESS" = true ]; then
    log_info "✓ All builds completed successfully!"
    log_info ""
    log_info "Build artifacts:"
    
    if [ "$TARGET" = "all" ] || [ "$TARGET" = "device" ]; then
        log_info "  Device libraries: $BUILD_DIR/device/lib/"
        log_info "  Device headers: $BUILD_DIR/device/include/"
    fi
    
    if [ "$TARGET" = "all" ] || [ "$TARGET" = "simulator" ]; then
        log_info "  Simulator libraries: $BUILD_DIR/simulator/lib/"
        log_info "  Simulator headers: $BUILD_DIR/simulator/include/"
    fi
    
    exit 0
else
    log_error "✗ Build failed. Check logs in $LOGS_DIR for details"
    exit 1
fi
