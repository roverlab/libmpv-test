# mpv iOS build scripts

This is a macOS shell script for cross-compiling [libmpv](https://github.com/mpv-player/mpv) for iOS (arm64 and x86_64). Includes build scripts for:

* mpv
* FFmpeg
* libass
* freetype
* harfbuzz
* fribidi
* uchardet

## 🚀 NEW: Swift Package Manager Support!

**If you're experiencing Xcode project corruption issues, use SPM instead!**

This project now supports Swift Package Manager (SPM) for cleaner dependency management and to avoid Xcode project file corruption issues. See [SPM_README.md](SPM_README.md) for details.

## Traditional Build Usage

### Prerequisites

1. Run `./download.sh` to download and unarchive the projects' source
2. Run `./build.sh -e ENVIRONMENT`, where environment is one of:

- `development`: builds arm64 and x86_64 fat static libraries, and builds mpv with debug symbols and no optimization.
- `distribution`: builds only arm64 static libraries, adds bitcode, and adds `-Os` to optimize for size and speed.

### Quick Start with SPM

```bash
# 1. Build the native libraries
./download.sh
./build.sh -e development

# 2. Run SPM tests directly
swift test

# 3. Generate Xcode project or use directly

### Building with Xcode (Traditional)

If you prefer to use the traditional Xcode project approach:

1. First build the libraries using the scripts above
2. Open `MPVTestApp.xcodeproj` in Xcode
3. Build and run tests

*Note: If you encounter "project is damaged" errors, use the SPM approach instead.*

## References

These scripts build upon [ybma-xbzheng/mpv-build-mac-iOS](https://github.com/ybma-xbzheng/mpv-build-mac-iOS) and [mpv-player/mpv-build](https://github.com/mpv-player/mpv-build)