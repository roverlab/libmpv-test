# iOS MPV Library Build System

Automated build system for compiling the MPV media player library and its dependencies for iOS platforms (ARM64 device and simulator).

## Overview

This project provides a complete build pipeline that cross-compiles MPV and all required dependencies for iOS using GitHub Actions automation. The resulting libraries can be integrated into iOS applications to enable advanced video playback capabilities.

### Features

- **ARM64 Support**: Builds for both iOS devices and simulators
- **Automated CI/CD**: GitHub Actions workflow for reproducible builds
- **Modular Architecture**: Separate build scripts for each dependency
- **Incremental Builds**: Smart caching to speed up development
- **Comprehensive Verification**: Automated checks for architecture and completeness
- **Easy Integration**: Organized artifacts ready for Xcode projects

## Prerequisites

### Required Software

- **macOS**: Version 12.0 (Monterey) or later
- **Xcode**: Version 14.0 or later with Command Line Tools
- **Homebrew**: For installing build tools

### Build Tools

Install the required build tools using Homebrew:

```bash
brew install meson ninja pkg-config
```

Verify installations:

```bash
xcodebuild -version
meson --version
ninja --version
pkg-config --version
```

### System Requirements

- **Disk Space**: At least 10 GB free for build artifacts
- **RAM**: 8 GB minimum (16 GB recommended)
- **Xcode Command Line Tools**: Install with `xcode-select --install`

## Quick Start

### Local Build

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd ios-mpv-library
   ```

2. **Validate your environment**:
   ```bash
   ./scripts/validate-environment.sh
   ```

3. **Run a clean build**:
   ```bash
   ./scripts/build-orchestrator.sh --clean --target all
   ```

4. **Find your artifacts**:
   - Device libraries: `build/device/lib/`
   - Device headers: `build/device/include/`
   - Simulator libraries: `build/simulator/lib/`
   - Simulator headers: `build/simulator/include/`

### Build Options

The build orchestrator supports several options:

```bash
./scripts/build-orchestrator.sh [OPTIONS]

Options:
  --clean          Clean all previous build artifacts before building
  --target TARGET  Build for specific target (device|simulator|all)
                   Default: all
  --incremental    Enable incremental build (skip unchanged dependencies)
  --verbose        Enable verbose logging
  -h, --help       Show help message
```

**Examples**:

```bash
# Clean build for all targets
./scripts/build-orchestrator.sh --clean --target all

# Build only for device
./scripts/build-orchestrator.sh --target device

# Incremental build (faster for development)
./scripts/build-orchestrator.sh --incremental --target simulator

# Verbose output for debugging
./scripts/build-orchestrator.sh --verbose
```

## GitHub Actions Workflow

### Automatic Builds

The GitHub Actions workflow automatically builds the library when:
- Code is pushed to `main` or `develop` branches
- Pull requests are opened against `main` or `develop`
- Manually triggered via workflow dispatch

### Workflow Features

- **macOS Runner**: Uses `macos-latest` with Xcode pre-installed
- **Smart Caching**: Caches source tarballs and compiled dependencies
- **Artifact Upload**: Automatically uploads build artifacts and logs
- **Build Verification**: Runs comprehensive checks on compiled libraries
- **Timeout Protection**: 120-minute timeout prevents runaway builds

### Accessing Build Artifacts

1. Navigate to the **Actions** tab in your GitHub repository
2. Select the completed workflow run
3. Download artifacts from the **Artifacts** section:
   - `ios-mpv-library-<sha>`: Compiled libraries and headers
   - `verification-report-<sha>`: Build verification results
   - `build-logs-<sha>`: Complete build logs

### Workflow Configuration

The workflow is defined in `.github/workflows/build-ios.yml` and includes:

- Environment setup and validation
- Dependency caching for faster builds
- Build orchestration for both targets
- Artifact verification and packaging
- Comprehensive error reporting

## Integration Guide

### Adding to Your iOS Project

1. **Download the build artifacts** from GitHub Actions or build locally

2. **Add libraries to your Xcode project**:
   - Drag the `lib/` folder into your Xcode project
   - Select "Create groups" and add to your target

3. **Add header search paths**:
   ```
   Project Settings → Build Settings → Header Search Paths
   Add: $(PROJECT_DIR)/path/to/include
   ```

4. **Link required frameworks**:
   ```
   Project Settings → Build Phases → Link Binary With Libraries
   Add:
   - AudioToolbox.framework
   - AVFoundation.framework
   - CoreMedia.framework
   - CoreVideo.framework
   - VideoToolbox.framework
   ```

5. **Configure linker flags**:
   ```
   Project Settings → Build Settings → Other Linker Flags
   Add: -lmpv -lffmpeg -lass -lfreetype -lharfbuzz -lfribidi -luchardet
   ```

### Basic Usage Example

```swift
import Foundation

// Initialize MPV
let mpv = mpv_create()

// Set options
mpv_set_option_string(mpv, "vo", "null")
mpv_set_option_string(mpv, "ao", "null")

// Initialize
mpv_initialize(mpv)

// Load and play video
let cmd = ["loadfile", "path/to/video.mp4"]
mpv_command(mpv, cmd)

// Cleanup
mpv_terminate_destroy(mpv)
```

### Architecture-Specific Integration

For projects supporting both device and simulator:

1. Use **device** libraries for physical iOS devices
2. Use **simulator** libraries for iOS Simulator
3. Configure build settings to select the correct library path based on target

## Project Structure

```
ios-mpv-library/
├── .github/
│   └── workflows/
│       └── build-ios.yml          # GitHub Actions workflow
├── scripts/
│   ├── build-orchestrator.sh      # Main build coordinator
│   ├── build-mpv.sh               # MPV build script
│   ├── build-ffmpeg.sh            # FFmpeg build script
│   ├── build-libass.sh            # libass build script
│   ├── build-freetype.sh          # FreeType build script
│   ├── build-harfbuzz.sh          # HarfBuzz build script
│   ├── build-fribidi.sh           # FriBidi build script
│   ├── build-uchardet.sh          # uchardet build script
│   ├── generate-cross-file.sh     # Meson cross-file generator
│   ├── validate-environment.sh    # Environment validation
│   ├── verify-build.sh            # Build verification
│   ├── package-artifacts.sh       # Artifact packaging
│   └── versions.txt               # Dependency versions
├── build/                         # Build output (generated)
│   ├── device/
│   │   ├── lib/                   # Device libraries
│   │   └── include/               # Device headers
│   └── simulator/
│       ├── lib/                   # Simulator libraries
│       └── include/               # Simulator headers
├── logs/                          # Build logs (generated)
└── cache/                         # Build cache (generated)
```

## Dependency Versions

Current versions (see `scripts/versions.txt`):

- **MPV**: 0.37.0
- **FFmpeg**: 6.1.1
- **libass**: 0.17.1
- **FreeType**: 2.13.2
- **HarfBuzz**: 8.3.0
- **FriBidi**: 1.0.13
- **uchardet**: 0.0.8

## Build Process Details

### Dependency Build Order

Dependencies are built in the following order to satisfy inter-dependencies:

1. **freetype** (no dependencies)
2. **fribidi** (no dependencies)
3. **uchardet** (no dependencies)
4. **harfbuzz** (depends on freetype)
5. **libass** (depends on freetype, fribidi, harfbuzz)
6. **FFmpeg** (independent)
7. **MPV** (depends on FFmpeg, libass, and transitively all others)

### Cross-Compilation Configuration

The build system uses Meson cross-files for iOS targets:

- **Target Architecture**: ARM64 (aarch64)
- **Minimum iOS Version**: 12.0
- **SDK Paths**: Automatically detected from Xcode
- **Compiler**: Clang from Xcode toolchain

### Build Artifacts

After a successful build, you'll find:

**Device Build** (`build/device/`):
- Static libraries (`.a` files) in `lib/`
- Header files in `include/`
- Architecture: ARM64 for physical iOS devices

**Simulator Build** (`build/simulator/`):
- Static libraries (`.a` files) in `lib/`
- Header files in `include/`
- Architecture: ARM64 for iOS Simulator

## Troubleshooting

### Common Issues

#### 1. Xcode Command Line Tools Not Found

**Error**: `xcode-select: error: tool 'xcodebuild' requires Xcode`

**Solution**:
```bash
xcode-select --install
# Or set Xcode path manually:
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

#### 2. iOS SDK Not Found

**Error**: `iOS SDK not found at: /path/to/SDK`

**Solution**:
```bash
# Verify Xcode installation
xcodebuild -version

# Check SDK paths
xcrun --sdk iphoneos --show-sdk-path
xcrun --sdk iphonesimulator --show-sdk-path

# Ensure Xcode is properly selected
sudo xcode-select --switch /Applications/Xcode.app
```

#### 3. Build Tools Missing

**Error**: `meson: command not found` or `ninja: command not found`

**Solution**:
```bash
# Install via Homebrew
brew install meson ninja pkg-config

# Verify installations
which meson
which ninja
which pkg-config
```

#### 4. Insufficient Disk Space

**Error**: `No space left on device`

**Solution**:
```bash
# Check available space
df -h

# Clean previous builds
./scripts/build-orchestrator.sh --clean

# Remove Xcode derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/*
```

#### 5. Build Fails for Specific Dependency

**Error**: `✗ <library> build failed for <target>`

**Solution**:
```bash
# Check the specific log file
cat logs/build-<library>-<target>.log

# Try building that dependency individually
./scripts/build-<library>.sh <target> arm64 <sdk-path>

# Enable verbose output for more details
./scripts/build-orchestrator.sh --verbose --target <target>
```

#### 6. Architecture Mismatch

**Error**: `Building for iOS, but linking in object file built for...`

**Solution**:
- Ensure you're using the correct library for your target (device vs simulator)
- Clean build and rebuild: `./scripts/build-orchestrator.sh --clean`
- Verify architecture with: `lipo -info build/device/lib/libmpv.a`

#### 7. Incremental Build Issues

**Error**: Build succeeds but library doesn't work correctly

**Solution**:
```bash
# Force a clean build
./scripts/build-orchestrator.sh --clean --target all

# Clear cache
rm -rf cache/
```

### Getting Help

If you encounter issues not covered here:

1. **Check the logs**: Build logs are in the `logs/` directory
2. **Review error output**: Look for specific error messages
3. **Verify environment**: Run `./scripts/validate-environment.sh`
4. **Check GitHub Actions**: Review workflow runs for CI-specific issues
5. **Open an issue**: Provide logs and environment details

### Debug Mode

For detailed debugging information:

```bash
# Enable verbose logging
./scripts/build-orchestrator.sh --verbose --target all

# Check individual build logs
ls -la logs/
cat logs/build-<library>-<target>.log

# Verify build artifacts
./scripts/verify-build.sh build/
```

## Performance Tips

### Faster Builds

1. **Use incremental builds** during development:
   ```bash
   ./scripts/build-orchestrator.sh --incremental
   ```

2. **Build specific targets** when testing:
   ```bash
   ./scripts/build-orchestrator.sh --target simulator
   ```

3. **Leverage caching** in GitHub Actions (automatically enabled)

4. **Use parallel compilation** (automatically configured based on CPU cores)

### Expected Build Times

- **Clean build (all targets)**: 60-90 minutes
- **Incremental build (MPV only)**: 5-10 minutes
- **Cached build (no changes)**: 2-3 minutes

## Contributing

Contributions are welcome! Please ensure:

1. All build scripts remain modular and well-documented
2. Changes are tested locally before pushing
3. GitHub Actions workflow passes successfully
4. Version numbers are updated in `scripts/versions.txt` when upgrading dependencies

## License

This build system is provided as-is. Please refer to individual dependency licenses:

- MPV: GPL/LGPL
- FFmpeg: GPL/LGPL
- libass: ISC License
- FreeType: FreeType License
- HarfBuzz: MIT License
- FriBidi: LGPL
- uchardet: MPL 1.1/GPL 2.0/LGPL 2.1

## Acknowledgments

Built with:
- [MPV](https://mpv.io/) - Media player
- [FFmpeg](https://ffmpeg.org/) - Multimedia framework
- [Meson](https://mesonbuild.com/) - Build system
- [GitHub Actions](https://github.com/features/actions) - CI/CD automation
