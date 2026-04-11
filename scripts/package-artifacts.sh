#!/bin/bash

# Artifact Packaging Script for iOS MPV Library
# Organizes libraries and headers into distribution structure
# Interface: package-artifacts.sh BUILD_DIR OUTPUT_DIR

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [package-artifacts.sh] $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [package-artifacts.sh] $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [package-artifacts.sh] $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] [package-artifacts.sh] $1"
}

# Validate arguments
if [ $# -ne 2 ]; then
    log_error "Usage: $0 BUILD_DIR OUTPUT_DIR"
    log_error "  BUILD_DIR  : Root directory containing build outputs"
    log_error "  OUTPUT_DIR : Destination for packaged artifacts"
    exit 1
fi

BUILD_DIR=$1
OUTPUT_DIR=$2

# Validate build directory
if [ ! -d "$BUILD_DIR" ]; then
    log_error "Build directory does not exist: $BUILD_DIR"
    exit 1
fi

log_info "=========================================="
log_info "Artifact Packaging"
log_info "=========================================="
log_info "Build directory: $BUILD_DIR"
log_info "Output directory: $OUTPUT_DIR"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Package directory structure
PACKAGE_NAME="ios-mpv-library-release"
PACKAGE_DIR="$OUTPUT_DIR/$PACKAGE_NAME"

# Clean existing package directory
if [ -d "$PACKAGE_DIR" ]; then
    log_info "Removing existing package directory..."
    rm -rf "$PACKAGE_DIR"
fi

# Create package structure
log_step "Creating package structure..."
mkdir -p "$PACKAGE_DIR/device/lib"
mkdir -p "$PACKAGE_DIR/device/include"
mkdir -p "$PACKAGE_DIR/simulator/lib"
mkdir -p "$PACKAGE_DIR/simulator/include"
mkdir -p "$PACKAGE_DIR/debug-symbols/device"
mkdir -p "$PACKAGE_DIR/debug-symbols/simulator"

log_info "✓ Package structure created"

# Function to copy libraries for a target
copy_libraries() {
    local target=$1
    local src_lib_dir="$BUILD_DIR/$target/lib"
    local dst_lib_dir="$PACKAGE_DIR/$target/lib"
    
    log_step "Copying $target libraries..."
    
    if [ ! -d "$src_lib_dir" ]; then
        log_error "Source library directory not found: $src_lib_dir"
        return 1
    fi
    
    # Copy all .a files
    local lib_count=0
    for lib in "$src_lib_dir"/*.a; do
        if [ -f "$lib" ]; then
            cp "$lib" "$dst_lib_dir/"
            ((lib_count++))
            log_info "  Copied: $(basename "$lib")"
        fi
    done
    
    if [ $lib_count -eq 0 ]; then
        log_warn "No libraries found in $src_lib_dir"
        return 1
    fi
    
    log_info "✓ Copied $lib_count libraries for $target"
    return 0
}

# Function to copy headers for a target
copy_headers() {
    local target=$1
    local src_include_dir="$BUILD_DIR/$target/include"
    local dst_include_dir="$PACKAGE_DIR/$target/include"
    
    log_step "Copying $target headers..."
    
    if [ ! -d "$src_include_dir" ]; then
        log_error "Source include directory not found: $src_include_dir"
        return 1
    fi
    
    # Copy all headers preserving directory structure
    cp -R "$src_include_dir"/* "$dst_include_dir/"
    
    # Count header files
    local header_count=$(find "$dst_include_dir" -type f \( -name "*.h" -o -name "*.hpp" \) | wc -l | tr -d ' ')
    
    log_info "✓ Copied $header_count header files for $target"
    return 0
}

# Function to extract and separate debug symbols
extract_debug_symbols() {
    local target=$1
    local lib_dir="$PACKAGE_DIR/$target/lib"
    local debug_dir="$PACKAGE_DIR/debug-symbols/$target"
    
    log_step "Extracting debug symbols for $target..."
    
    local symbol_count=0
    
    for lib in "$lib_dir"/*.a; do
        if [ -f "$lib" ]; then
            local lib_name=$(basename "$lib")
            local debug_file="$debug_dir/${lib_name}.dSYM"
            
            # Check if library has debug symbols
            if dsymutil "$lib" -o "$debug_file" 2>/dev/null; then
                ((symbol_count++))
                log_info "  Extracted: ${lib_name}.dSYM"
            fi
        fi
    done
    
    if [ $symbol_count -eq 0 ]; then
        log_info "  No debug symbols found for $target"
        # Remove empty debug symbols directory
        rmdir "$debug_dir" 2>/dev/null || true
    else
        log_info "✓ Extracted $symbol_count debug symbol files for $target"
    fi
    
    return 0
}

# Function to collect library metadata
collect_library_metadata() {
    local target=$1
    local lib_dir="$PACKAGE_DIR/$target/lib"
    local -n libs_array=$2
    
    for lib in "$lib_dir"/*.a; do
        if [ -f "$lib" ]; then
            local lib_name=$(basename "$lib")
            local lib_size=$(stat -f%z "$lib" 2>/dev/null || stat -c%s "$lib" 2>/dev/null)
            local lib_arch=$(lipo -info "$lib" 2>/dev/null | grep -o "arm64" || echo "unknown")
            
            libs_array+=("$lib_name")
        fi
    done
}

# Function to generate manifest.json
generate_manifest() {
    log_step "Generating manifest.json..."
    
    local manifest_file="$PACKAGE_DIR/manifest.json"
    local build_date=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    # Read version from versions.txt if available
    local mpv_version="unknown"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local versions_file="$script_dir/versions.txt"
    
    if [ -f "$versions_file" ]; then
        mpv_version=$(grep "^MPV_VERSION=" "$versions_file" | cut -d'=' -f2 || echo "unknown")
    fi
    
    # Collect library lists for each target
    declare -a device_libs=()
    declare -a simulator_libs=()
    
    if [ -d "$PACKAGE_DIR/device/lib" ]; then
        collect_library_metadata "device" device_libs
    fi
    
    if [ -d "$PACKAGE_DIR/simulator/lib" ]; then
        collect_library_metadata "simulator" simulator_libs
    fi
    
    # Generate JSON manifest
    cat > "$manifest_file" << EOF
{
  "version": "$mpv_version",
  "build_date": "$build_date",
  "targets": {
EOF
    
    # Add device target if exists
    if [ ${#device_libs[@]} -gt 0 ]; then
        cat >> "$manifest_file" << EOF
    "device": {
      "architecture": "arm64",
      "sdk": "iphoneos",
      "min_ios_version": "12.0",
      "libraries": [
EOF
        
        for i in "${!device_libs[@]}"; do
            local lib="${device_libs[$i]}"
            if [ $i -eq $((${#device_libs[@]} - 1)) ]; then
                echo "        \"$lib\"" >> "$manifest_file"
            else
                echo "        \"$lib\"," >> "$manifest_file"
            fi
        done
        
        echo "      ]" >> "$manifest_file"
        
        # Add comma if simulator target exists
        if [ ${#simulator_libs[@]} -gt 0 ]; then
            echo "    }," >> "$manifest_file"
        else
            echo "    }" >> "$manifest_file"
        fi
    fi
    
    # Add simulator target if exists
    if [ ${#simulator_libs[@]} -gt 0 ]; then
        cat >> "$manifest_file" << EOF
    "simulator": {
      "architecture": "arm64",
      "sdk": "iphonesimulator",
      "min_ios_version": "12.0",
      "libraries": [
EOF
        
        for i in "${!simulator_libs[@]}"; do
            local lib="${simulator_libs[$i]}"
            if [ $i -eq $((${#simulator_libs[@]} - 1)) ]; then
                echo "        \"$lib\"" >> "$manifest_file"
            else
                echo "        \"$lib\"," >> "$manifest_file"
            fi
        done
        
        echo "      ]" >> "$manifest_file"
        echo "    }" >> "$manifest_file"
    fi
    
    # Close JSON
    cat >> "$manifest_file" << EOF
  }
}
EOF
    
    log_info "✓ Generated manifest.json"
    return 0
}

# Function to create README
create_readme() {
    log_step "Creating README.md..."
    
    local readme_file="$PACKAGE_DIR/README.md"
    local build_date=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$readme_file" << 'EOF'
# iOS MPV Library Release

This package contains pre-compiled MPV library and its dependencies for iOS platforms.

## Contents

- `device/` - Libraries and headers for iOS devices (ARM64)
- `simulator/` - Libraries and headers for iOS simulator (ARM64)
- `debug-symbols/` - Debug symbols for debugging (if available)
- `manifest.json` - Build metadata and artifact list

## Integration

### Xcode Project Setup

1. Add library search paths:
   - Device: `$(PROJECT_DIR)/path/to/device/lib`
   - Simulator: `$(PROJECT_DIR)/path/to/simulator/lib`

2. Add header search paths:
   - `$(PROJECT_DIR)/path/to/device/include`
   - `$(PROJECT_DIR)/path/to/simulator/include`

3. Link against libraries:
   - `libmpv.a`
   - `libavcodec.a`, `libavformat.a`, `libavutil.a`, `libswscale.a`, `libswresample.a`
   - `libass.a`
   - `libfreetype.a`, `libharfbuzz.a`, `libfribidi.a`, `libuchardet.a`

4. Add required system frameworks:
   - `AVFoundation.framework`
   - `CoreMedia.framework`
   - `CoreVideo.framework`
   - `VideoToolbox.framework`

### Basic Usage

```objc
#import <mpv/client.h>

// Initialize MPV
mpv_handle *mpv = mpv_create();
mpv_initialize(mpv);

// Load and play video
mpv_command_string(mpv, "loadfile video.mp4");

// Cleanup
mpv_terminate_destroy(mpv);
```

## Requirements

- iOS 12.0 or later
- Xcode 14.0 or later
- ARM64 architecture (modern iOS devices and simulators)

## Build Information

See `manifest.json` for detailed build metadata including:
- MPV version
- Build date
- Target architectures
- Complete library list

## License

MPV and its dependencies are licensed under various open-source licenses.
Please refer to the individual project licenses for details.

EOF
    
    log_info "✓ Created README.md"
    return 0
}

# Function to create compressed archive
create_archive() {
    log_step "Creating compressed archive..."
    
    local archive_name="${PACKAGE_NAME}.tar.gz"
    local archive_path="$OUTPUT_DIR/$archive_name"
    
    # Remove existing archive
    if [ -f "$archive_path" ]; then
        rm -f "$archive_path"
    fi
    
    # Create tar.gz archive
    cd "$OUTPUT_DIR"
    
    if tar -czf "$archive_name" "$PACKAGE_NAME"; then
        local archive_size=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null)
        local archive_size_mb=$((archive_size / 1024 / 1024))
        
        log_info "✓ Created archive: $archive_name (${archive_size_mb} MB)"
        return 0
    else
        log_error "Failed to create archive"
        return 1
    fi
}

# Main packaging workflow
PACKAGING_SUCCESS=true

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

# Copy libraries and headers for each target
for target in "${TARGETS[@]}"; do
    if ! copy_libraries "$target"; then
        PACKAGING_SUCCESS=false
    fi
    
    if ! copy_headers "$target"; then
        PACKAGING_SUCCESS=false
    fi
    
    # Extract debug symbols (non-fatal if fails)
    extract_debug_symbols "$target" || true
done

# Generate manifest
if ! generate_manifest; then
    PACKAGING_SUCCESS=false
fi

# Create README
if ! create_readme; then
    PACKAGING_SUCCESS=false
fi

# Create compressed archive
if ! create_archive; then
    PACKAGING_SUCCESS=false
fi

# Summary
log_info "=========================================="
log_info "Packaging Summary"
log_info "=========================================="

if [ "$PACKAGING_SUCCESS" = true ]; then
    log_info "✓ Packaging completed successfully!"
    log_info ""
    log_info "Package location: $PACKAGE_DIR"
    log_info "Archive: $OUTPUT_DIR/${PACKAGE_NAME}.tar.gz"
    log_info ""
    log_info "Package contents:"
    
    for target in "${TARGETS[@]}"; do
        local lib_count=$(find "$PACKAGE_DIR/$target/lib" -name "*.a" | wc -l | tr -d ' ')
        local header_count=$(find "$PACKAGE_DIR/$target/include" -type f \( -name "*.h" -o -name "*.hpp" \) | wc -l | tr -d ' ')
        
        log_info "  $target: $lib_count libraries, $header_count headers"
    done
    
    exit 0
else
    log_error "✗ Packaging failed"
    exit 1
fi
