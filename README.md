# Libmpv for iOS

[![Build and Release](https://github.com/nicholaslee119/libmpv-test/actions/workflows/build-ios.yml/badge.svg)](https://github.com/nicholaslee119/libmpv-test/actions/workflows/build-ios.yml)
[![Release](https://img.shields.io/github/v/release/nicholaslee119/libmpv-test)](https://github.com/nicholaslee119/libmpv-test/releases)
[![License](https://img.shields.io/github/license/nicholaslee119/libmpv-test)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%2013+%20-lightgrey)](https://www.apple.com/ios/)

A pre-built [libmpv](https://github.com/mpv-player/mpv) static library for iOS, distributed as a Swift Package Manager package. This allows you to easily integrate mpv's powerful video playback capabilities into your iOS applications.

## Features

- 🎬 **Pre-built binaries** - No need to compile mpv and its dependencies yourself
- 📦 **Swift Package Manager** - Easy integration with Xcode projects
- 🔧 **Multi-architecture support** - Includes both device (arm64) and simulator (arm64-simulator) slices
- 🚀 **Optimized builds** - Compiled with `-Os` optimization and bitcode support for device builds
- 📱 **iOS 13+ support** - Compatible with modern iOS versions

## Installation

### Swift Package Manager (Recommended)

1. In Xcode, go to **File > Add Packages...**
2. Enter the repository URL:
   ```
   https://github.com/nicholaslee119/libmpv-test
   ```
3. Select the version you want to use
4. Click **Add Package**

### Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nicholaslee119/libmpv-test", from: "0.39.0")
]
```

## Usage

### Basic Setup

1. Import the module:
   ```swift
   import Libmpv
   ```

2. Create an mpv instance:
   ```swift
   let mpv = mpv_create()
   mpv_set_option_string(mpv, "vo", "gpu")
   mpv_initialize(mpv)
   ```

3. Load a video:
   ```swift
   let path = Bundle.main.path(forResource: "video", ofType: "mp4")!
   mpv_command_string(mpv, "loadfile \"\(path)\"")
   ```

### Example: Simple Video Player

```swift
import UIKit
import Libmpv

class VideoPlayerViewController: UIViewController {
    private var mpv: OpaquePointer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupMPV()
    }
    
    private func setupMPV() {
        mpv = mpv_create()
        guard let mpv = mpv else { return }
        
        // Configure mpv
        mpv_set_option_string(mpv, "vo", "gpu")
        mpv_set_option_string(mpv, "hwdec", "auto")
        
        // Initialize
        mpv_initialize(mpv)
        
        // Load video
        if let videoPath = Bundle.main.path(forResource: "sample", ofType: "mp4") {
            mpv_command_string(mpv, "loadfile \"\(videoPath)\"")
        }
    }
    
    deinit {
        if let mpv = mpv {
            mpv_terminate_destroy(mpv)
        }
    }
}
```

## API Reference

This package provides access to the full libmpv C API. Key functions include:

### Core Functions

| Function | Description |
|----------|-------------|
| `mpv_create()` | Create a new mpv instance |
| `mpv_initialize()` | Initialize the mpv instance |
| `mpv_terminate_destroy()` | Destroy the mpv instance |
| `mpv_set_option_string()` | Set a string option |
| `mpv_set_option_flag()` | Set a boolean option |
| `mpv_command_string()` | Execute a command |
| `mpv_get_property_string()` | Get a string property |
| `mpv_set_property_string()` | Set a string property |

For complete API documentation, see the [mpv manual](https://mpv.io/manual/master/) and [libmpv client API](https://mpv.io/manual/master/#command-interface).

## Included Libraries

This package includes the following pre-compiled libraries:

| Library | Version | Purpose |
|---------|---------|---------|
| mpv | 0.39.0 | Video player |
| FFmpeg | 7.0 | Media processing |
| libass | 0.17.3 | Subtitle rendering |
| freetype | 2.13.2 | Font rendering |
| harfbuzz | 8.4.0 | Text shaping |
| fribidi | 1.0.13 | Bidirectional text |
| uchardet | 0.0.5 | Character encoding detection |

## Building from Source

If you need to build the library yourself:

### Prerequisites

- macOS with Xcode 15+
- Homebrew

### Build Steps

```bash
# Clone the repository
git clone https://github.com/nicholaslee119/libmpv-test.git
cd libmpv-test

# Download source code
./download.sh

# Build for distribution (arm64 device)
./build.sh -e distribution

# Build for simulator (optional)
./build.sh -e simulator

# Create XCFramework
mkdir -p include_temp
cp scratch/arm64/include/mpv/*.h include_temp/

xcodebuild -create-xcframework \
  -library scratch/arm64/lib/libmpv.a \
  -headers include_temp \
  -library scratch/arm64-simulator/lib/libmpv.a \
  -output lib/Libmpv.xcframework
```

## Architecture Support

| Architecture | Platform | Status |
|--------------|----------|--------|
| arm64 | iOS Device | ✅ Supported |
| arm64 | iOS Simulator (Apple Silicon Mac) | ✅ Supported |

Note: x86_64 simulator (Intel Mac) is not included in the pre-built binaries.

## License

This project is provided as-is. The underlying mpv and FFmpeg libraries are licensed under their respective licenses:

- **mpv**: LGPL v2.1+ or GPL v2+ (configurable)
- **FFmpeg**: LGPL v2.1+ or GPL v2+ (depending on configuration)
- **libass**: ISC
- **freetype**: FTL or GPL
- **harfbuzz**: MIT
- **fribidi**: LGPL v2.1+
- **uchardet**: MPL v1.1 or GPL v2+ or LGPL v2.1+

Please ensure your usage complies with these licenses.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Credits

- [mpv](https://mpv.io/) - The best video player
- [FFmpeg](https://ffmpeg.org/) - Multimedia framework
- Build scripts inspired by [mpv-player/mpv-build](https://github.com/mpv-player/mpv-build)

## Support

If you encounter any issues or have questions:

1. Check the [mpv manual](https://mpv.io/manual/master/)
2. Open an [issue](https://github.com/nicholaslee119/libmpv-test/issues)
