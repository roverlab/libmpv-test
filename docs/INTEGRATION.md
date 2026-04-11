# iOS MPV Library Integration Guide

This guide provides step-by-step instructions for integrating the MPV library into your iOS application.

## Prerequisites

- Xcode 14.0 or later
- iOS deployment target 12.0 or later
- ARM64 architecture support (modern iOS devices and simulators)
- Basic knowledge of Xcode project configuration

## Quick Start

### 1. Obtain the Library

**Option A: Download from GitHub Actions**
1. Navigate to the **Actions** tab in the repository
2. Select a successful workflow run
3. Download the `ios-mpv-library-<sha>` artifact
4. Extract the archive to get the library files

**Option B: Build Locally**
```bash
./scripts/build-orchestrator.sh --clean --target all
```

After building, find the artifacts in:
- Device: `build/device/`
- Simulator: `build/simulator/`

### 2. Add Libraries to Your Xcode Project

1. **Create a Libraries folder** in your project directory:
   ```
   YourProject/
   ├── Libraries/
   │   ├── device/
   │   │   ├── lib/
   │   │   └── include/
   │   └── simulator/
   │       ├── lib/
   │       └── include/
   ```

2. **Copy the library files**:
   - Copy `build/device/lib/` and `build/device/include/` to `Libraries/device/`
   - Copy `build/simulator/lib/` and `build/simulator/include/` to `Libraries/simulator/`

3. **Add libraries to Xcode**:
   - In Xcode, select your project in the navigator
   - Select your app target
   - Go to **Build Phases** → **Link Binary With Libraries**
   - Click **+** and choose **Add Other...** → **Add Files...**
   - Navigate to `Libraries/device/lib/` and add all `.a` files

## Xcode Project Configuration

### Configure Build Settings

#### 1. Library Search Paths

Add architecture-specific library search paths:

1. Select your project → Select your target → **Build Settings**
2. Search for **Library Search Paths**
3. Add the following (adjust paths to match your project structure):

```
$(PROJECT_DIR)/Libraries/device/lib
$(PROJECT_DIR)/Libraries/simulator/lib
```

For architecture-specific configuration:
```
"$(PROJECT_DIR)/Libraries/$(PLATFORM_NAME)/lib"
```

#### 2. Header Search Paths

Add header search paths for MPV and dependencies:

1. Search for **Header Search Paths** in Build Settings
2. Add:

```
$(PROJECT_DIR)/Libraries/device/include
$(PROJECT_DIR)/Libraries/simulator/include
```

Or use architecture-specific:
```
"$(PROJECT_DIR)/Libraries/$(PLATFORM_NAME)/include"
```

Mark these as **recursive** if needed.

#### 3. Other Linker Flags

Add required linker flags:

1. Search for **Other Linker Flags** in Build Settings
2. Add the following flags:

```
-lmpv
-lavcodec
-lavformat
-lavutil
-lswscale
-lswresample
-lavfilter
-lass
-lfreetype
-lharfbuzz
-lfribidi
-luchardet
-lz
-lbz2
-liconv
```

#### 4. Link System Frameworks

Add required iOS frameworks:

1. Go to **Build Phases** → **Link Binary With Libraries**
2. Click **+** and add:
   - `AVFoundation.framework`
   - `AudioToolbox.framework`
   - `CoreMedia.framework`
   - `CoreVideo.framework`
   - `VideoToolbox.framework`
   - `CoreGraphics.framework`
   - `Foundation.framework`

### Architecture-Specific Configuration (Advanced)

For projects that need explicit architecture handling:

1. **Create separate build configurations** for device and simulator
2. **Use conditional library paths**:

```
// Device configuration
LIBRARY_SEARCH_PATHS = $(PROJECT_DIR)/Libraries/device/lib
HEADER_SEARCH_PATHS = $(PROJECT_DIR)/Libraries/device/include

// Simulator configuration
LIBRARY_SEARCH_PATHS = $(PROJECT_DIR)/Libraries/simulator/lib
HEADER_SEARCH_PATHS = $(PROJECT_DIR)/Libraries/simulator/include
```

## Code Integration

### Objective-C Integration

#### 1. Import MPV Headers

```objc
#import <mpv/client.h>
```

#### 2. Basic Initialization

```objc
@interface VideoPlayerController : UIViewController {
    mpv_handle *mpv;
}
@end

@implementation VideoPlayerController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Create MPV instance
    mpv = mpv_create();
    if (!mpv) {
        NSLog(@"Failed to create MPV instance");
        return;
    }
    
    // Configure MPV options
    mpv_set_option_string(mpv, "vo", "null");  // No video output (audio only)
    // Or use "gpu" for video rendering
    
    // Initialize MPV
    if (mpv_initialize(mpv) < 0) {
        NSLog(@"Failed to initialize MPV");
        mpv_terminate_destroy(mpv);
        mpv = NULL;
        return;
    }
    
    NSLog(@"MPV initialized successfully");
}

- (void)loadVideo:(NSString *)path {
    if (!mpv) return;
    
    const char *cmd[] = {"loadfile", [path UTF8String], NULL};
    mpv_command(mpv, cmd);
}

- (void)play {
    if (!mpv) return;
    
    mpv_set_property_string(mpv, "pause", "no");
}

- (void)pause {
    if (!mpv) return;
    
    mpv_set_property_string(mpv, "pause", "yes");
}

- (void)dealloc {
    if (mpv) {
        mpv_terminate_destroy(mpv);
        mpv = NULL;
    }
}

@end
```

### Swift Integration

#### 1. Create Bridging Header

Create a bridging header file (e.g., `YourProject-Bridging-Header.h`):

```objc
#import <mpv/client.h>
```

Configure the bridging header in Build Settings:
- Search for **Objective-C Bridging Header**
- Set to: `$(PROJECT_DIR)/YourProject/YourProject-Bridging-Header.h`

#### 2. Swift Wrapper Class

```swift
import Foundation
import AVFoundation

class MPVPlayer {
    private var mpv: OpaquePointer?
    
    init?() {
        mpv = mpv_create()
        guard mpv != nil else {
            print("Failed to create MPV instance")
            return nil
        }
        
        // Configure options
        mpv_set_option_string(mpv, "vo", "null")
        
        // Initialize
        if mpv_initialize(mpv) < 0 {
            print("Failed to initialize MPV")
            mpv_terminate_destroy(mpv)
            mpv = nil
            return nil
        }
        
        print("MPV initialized successfully")
    }
    
    func loadVideo(path: String) {
        guard let mpv = mpv else { return }
        
        let cmd: [UnsafePointer<CChar>?] = [
            "loadfile".cString(using: .utf8)?.withUnsafeBufferPointer { $0.baseAddress },
            path.cString(using: .utf8)?.withUnsafeBufferPointer { $0.baseAddress },
            nil
        ]
        
        cmd.withUnsafeBufferPointer { buffer in
            mpv_command(mpv, buffer.baseAddress)
        }
    }
    
    func play() {
        guard let mpv = mpv else { return }
        mpv_set_property_string(mpv, "pause", "no")
    }
    
    func pause() {
        guard let mpv = mpv else { return }
        mpv_set_property_string(mpv, "pause", "yes")
    }
    
    func seek(to position: Double) {
        guard let mpv = mpv else { return }
        var pos = position
        mpv_set_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &pos)
    }
    
    func getProperty<T>(_ name: String, format: mpv_format) -> T? {
        guard let mpv = mpv else { return nil }
        
        var value: T?
        mpv_get_property(mpv, name, format, &value)
        return value
    }
    
    deinit {
        if let mpv = mpv {
            mpv_terminate_destroy(mpv)
        }
    }
}

// Usage example
class VideoViewController: UIViewController {
    var player: MPVPlayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        player = MPVPlayer()
        
        // Load a video
        if let videoPath = Bundle.main.path(forResource: "sample", ofType: "mp4") {
            player?.loadVideo(path: videoPath)
            player?.play()
        }
    }
}
```

## Advanced Configuration

### Video Rendering with OpenGL

For video playback with rendering:

```objc
// Configure video output
mpv_set_option_string(mpv, "vo", "gpu");
mpv_set_option_string(mpv, "gpu-context", "ios");

// Set up OpenGL rendering context
// (Requires additional OpenGL ES setup)
```

### Event Handling

```objc
- (void)setupEventHandling {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (self->mpv) {
            mpv_event *event = mpv_wait_event(self->mpv, 1.0);
            
            if (event->event_id == MPV_EVENT_NONE) {
                continue;
            }
            
            switch (event->event_id) {
                case MPV_EVENT_PLAYBACK_RESTART:
                    NSLog(@"Playback started");
                    break;
                    
                case MPV_EVENT_END_FILE:
                    NSLog(@"Playback ended");
                    break;
                    
                case MPV_EVENT_PROPERTY_CHANGE: {
                    mpv_event_property *prop = (mpv_event_property *)event->data;
                    NSLog(@"Property changed: %s", prop->name);
                    break;
                }
                    
                case MPV_EVENT_SHUTDOWN:
                    return;
                    
                default:
                    break;
            }
        }
    });
}
```

### Property Observation

```objc
// Observe time position
mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);

// Observe duration
mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE);

// Observe pause state
mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG);
```

## Common Configuration Options

### Audio-Only Playback

```objc
mpv_set_option_string(mpv, "vo", "null");
mpv_set_option_string(mpv, "video", "no");
```

### Hardware Decoding

```objc
mpv_set_option_string(mpv, "hwdec", "auto");
mpv_set_option_string(mpv, "hwdec-codecs", "all");
```

### Logging

```objc
mpv_set_option_string(mpv, "terminal", "yes");
mpv_set_option_string(mpv, "msg-level", "all=v");
```

### Network Streaming

```objc
// Load network stream
const char *cmd[] = {"loadfile", "https://example.com/video.mp4", NULL};
mpv_command(mpv, cmd);

// Configure network options
mpv_set_option_string(mpv, "cache", "yes");
mpv_set_option_string(mpv, "cache-secs", "10");
```

## Troubleshooting

### Build Errors

#### "Library not found"

**Solution**: Verify library search paths are correct and libraries exist:
```bash
ls -la Libraries/device/lib/
ls -la Libraries/simulator/lib/
```

#### "Undefined symbols for architecture arm64"

**Solution**: Ensure all required libraries are linked:
- Check **Other Linker Flags** includes all library names
- Verify all system frameworks are added
- Check that you're using the correct library for your target (device vs simulator)

#### "Header file not found"

**Solution**: 
- Verify **Header Search Paths** in Build Settings
- Ensure paths point to the `include/` directory
- Check that header files exist in the specified location

### Runtime Errors

#### "MPV initialization failed"

**Possible causes**:
- Missing or incompatible library files
- Incorrect architecture (using simulator library on device or vice versa)
- Missing system frameworks

**Solution**:
```objc
// Add error checking
int result = mpv_initialize(mpv);
if (result < 0) {
    NSLog(@"MPV initialization failed with error: %d", result);
    NSLog(@"Error string: %s", mpv_error_string(result));
}
```

#### "Video playback fails"

**Solution**:
- Check file path is correct and accessible
- Verify video format is supported
- Enable logging to see detailed error messages:
```objc
mpv_set_option_string(mpv, "msg-level", "all=v");
```

### Architecture Verification

Verify library architecture matches your target:

```bash
# Check library architecture
lipo -info Libraries/device/lib/libmpv.a
# Should output: Non-fat file: ... is architecture: arm64

lipo -info Libraries/simulator/lib/libmpv.a
# Should output: Non-fat file: ... is architecture: arm64
```

## Sample Xcode Project Configuration

### Complete Build Settings Summary

```
// Library Search Paths
LIBRARY_SEARCH_PATHS = $(PROJECT_DIR)/Libraries/$(PLATFORM_NAME)/lib

// Header Search Paths
HEADER_SEARCH_PATHS = $(PROJECT_DIR)/Libraries/$(PLATFORM_NAME)/include

// Other Linker Flags
OTHER_LDFLAGS = -lmpv -lavcodec -lavformat -lavutil -lswscale -lswresample -lavfilter -lass -lfreetype -lharfbuzz -lfribidi -luchardet -lz -lbz2 -liconv

// Frameworks
FRAMEWORKS = AVFoundation AudioToolbox CoreMedia CoreVideo VideoToolbox CoreGraphics Foundation

// Architectures
ARCHS = arm64

// Deployment Target
IPHONEOS_DEPLOYMENT_TARGET = 12.0
```

### Info.plist Permissions

If accessing media files or network resources, add required permissions:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Access photos for video playback</string>

<key>NSCameraUsageDescription</key>
<string>Access camera for video recording</string>

<key>NSMicrophoneUsageDescription</key>
<string>Access microphone for audio recording</string>

<!-- For network access -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

## Performance Optimization

### Memory Management

```objc
// Release resources when not needed
- (void)applicationDidEnterBackground:(UIApplication *)application {
    if (mpv) {
        mpv_set_property_string(mpv, "pause", "yes");
    }
}

- (void)applicationWillTerminate:(UIApplication *)application {
    if (mpv) {
        mpv_terminate_destroy(mpv);
        mpv = NULL;
    }
}
```

### Threading

MPV operations should be performed on background threads:

```objc
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    // MPV operations here
    const char *cmd[] = {"loadfile", path, NULL};
    mpv_command(self->mpv, cmd);
});
```

## Additional Resources

- **MPV Documentation**: https://mpv.io/manual/stable/
- **MPV Client API**: https://github.com/mpv-player/mpv/blob/master/libmpv/client.h
- **FFmpeg Documentation**: https://ffmpeg.org/documentation.html

## Support

For issues specific to this build system:
1. Check the main [README.md](../README.md) troubleshooting section
2. Review build logs in the `logs/` directory
3. Verify your environment with `./scripts/validate-environment.sh`
4. Open an issue on GitHub with detailed error messages and environment information

## License

MPV and its dependencies are licensed under various open-source licenses. Please review:
- MPV: GPL/LGPL
- FFmpeg: GPL/LGPL
- libass: ISC License
- FreeType: FreeType License
- HarfBuzz: MIT License
- FriBidi: LGPL
- uchardet: MPL 1.1/GPL 2.0/LGPL 2.1

Ensure your application complies with these licenses when distributing.
