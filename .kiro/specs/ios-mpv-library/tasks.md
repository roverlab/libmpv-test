# Implementation Plan: iOS MPV Library Build System

## Overview

This implementation plan breaks down the iOS MPV library build system into discrete coding tasks. The system will compile MPV and its dependencies for iOS ARM64 architecture (device and simulator) using GitHub Actions automation. Each task builds incrementally toward a complete, automated build pipeline with proper verification and packaging.

## Tasks

- [x] 1. Set up project structure and configuration files
  - Create directory structure: `scripts/`, `.github/workflows/`, `build/`, `logs/`
  - Create `scripts/versions.txt` to track dependency versions
  - Create `.gitignore` to exclude build artifacts and logs
  - _Requirements: 8.1, 8.3, 6.1_

- [ ] 2. Implement environment setup and validation
  - [x] 2.1 Create environment validation script
    - Write `scripts/validate-environment.sh` to check for Xcode, Meson, Ninja, pkg-config
    - Validate iOS SDK paths for both device and simulator
    - Check minimum macOS version and available disk space
    - _Requirements: 5.1, 5.2, 9.4_
  
  - [ ]* 2.2 Write unit tests for environment validation
    - Test SDK path detection logic
    - Test error messages for missing tools
    - _Requirements: 5.1, 9.4_

- [ ] 3. Create cross-compilation configuration
  - [x] 3.1 Generate Meson cross-files for iOS targets
    - Write `scripts/generate-cross-file.sh` to create `ios-device-cross.txt` and `ios-simulator-cross.txt`
    - Configure compiler flags: `-arch arm64`, `-mios-version-min=12.0`, `-isysroot`
    - Set binaries (clang, ar, strip) and host machine properties
    - _Requirements: 5.1, 5.2, 5.3, 5.4_
  
  - [ ]* 3.2 Test cross-file generation
    - Verify generated cross-files have correct architecture and SDK paths
    - Test with different Xcode versions
    - _Requirements: 5.1, 5.4_

- [ ] 4. Implement dependency build scripts
  - [x] 4.1 Create freetype build script
    - Write `scripts/build-freetype.sh` with interface: `TARGET ARCH SDK_PATH`
    - Download source tarball if not cached
    - Configure with autotools for iOS cross-compilation
    - Compile and install to `build/$TARGET/`
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 8.1, 8.4_
  
  - [x] 4.2 Create fribidi build script
    - Write `scripts/build-fribidi.sh` following same interface pattern
    - Configure for iOS ARM64 target
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 8.1_
  
  - [x] 4.3 Create uchardet build script
    - Write `scripts/build-uchardet.sh` following same interface pattern
    - Use CMake with iOS toolchain configuration
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 8.1_
  
  - [x] 4.4 Create harfbuzz build script
    - Write `scripts/build-harfbuzz.sh` with dependency on freetype
    - Set `PKG_CONFIG_PATH` to find freetype
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 8.1_
  
  - [x] 4.5 Create libass build script
    - Write `scripts/build-libass.sh` with dependencies on freetype, fribidi, harfbuzz
    - Configure with all required dependency paths
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 8.1_
  
  - [x] 4.6 Create FFmpeg build script
    - Write `scripts/build-ffmpeg.sh` with extensive configure flags
    - Disable incompatible features for iOS (videotoolbox may need special handling)
    - Enable required decoders and demuxers for MPV
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 5.5, 8.1_

- [x] 5. Checkpoint - Test individual dependency builds
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 6. Implement MPV build script
  - [x] 6.1 Create MPV build script
    - Write `scripts/build-mpv.sh` with interface: `TARGET ARCH SDK_PATH DEPS_PATH`
    - Configure Meson with cross-file and dependency paths
    - Set options: `-Dlibmpv=true`, `-Dcplayer=false`, `-Dlua=disabled`, `-Djavascript=disabled`
    - Build static library and install headers
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 5.5, 8.2_
  
  - [ ]* 6.2 Write integration tests for MPV build
    - Test MPV links correctly against all dependencies
    - Verify libmpv.a contains expected symbols
    - _Requirements: 1.3, 1.4_

- [ ] 7. Implement build orchestrator
  - [x] 7.1 Create main orchestration script
    - Write `scripts/build-orchestrator.sh` with options: `--clean`, `--target`, `--incremental`, `--verbose`
    - Implement dependency build order: freetype → fribidi → uchardet → harfbuzz → libass → FFmpeg → MPV
    - Execute builds for both device and simulator targets
    - Aggregate logs to `logs/` directory
    - _Requirements: 8.3, 8.4, 9.1, 9.2, 9.3, 9.5_
  
  - [x] 7.2 Implement incremental build logic
    - Track source file timestamps in cache
    - Skip unchanged dependencies when `--incremental` flag is set
    - Implement `--clean` option to remove all build artifacts
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_
  
  - [ ]* 7.3 Write integration tests for orchestrator
    - Test clean build completes successfully
    - Test incremental build skips unchanged dependencies
    - Test error propagation from dependency scripts
    - _Requirements: 8.3, 10.1, 10.2_

- [ ] 8. Implement verification module
  - [x] 8.1 Create build verification script
    - Write `scripts/verify-build.sh` with interface: `BUILD_DIR`
    - Check all expected library files exist and are non-empty
    - Use `lipo -info` to verify ARM64 architecture for each library
    - Validate presence of required headers (mpv/client.h, etc.)
    - Generate verification report to `logs/verification.log`
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 3.4_
  
  - [ ]* 8.2 Write unit tests for verification logic
    - Test with valid and invalid library files
    - Test architecture detection with sample binaries
    - Test error reporting for missing files
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

- [ ] 9. Implement packaging module
  - [x] 9.1 Create artifact packaging script
    - Write `scripts/package-artifacts.sh` with interface: `BUILD_DIR OUTPUT_DIR`
    - Organize libraries and headers into distribution structure
    - Generate `manifest.json` with build metadata and artifact list
    - Create compressed archive: `ios-mpv-library-release.tar.gz`
    - Separate debug symbols if present
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_
  
  - [ ]* 9.2 Write unit tests for packaging
    - Test manifest.json generation with sample artifacts
    - Test directory structure creation
    - Verify archive integrity
    - _Requirements: 6.3, 6.4_

- [x] 10. Checkpoint - Test complete build pipeline locally
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 11. Implement GitHub Actions workflow
  - [x] 11.1 Create GitHub Actions workflow file
    - Write `.github/workflows/build-ios.yml`
    - Configure macOS runner with `macos-latest`
    - Set timeout to 120 minutes
    - Add steps: checkout, setup environment, run build orchestrator, upload artifacts
    - _Requirements: 4.1, 4.2, 4.3, 4.5_
  
  - [x] 11.2 Implement caching strategy
    - Cache downloaded source tarballs using `actions/cache@v3`
    - Cache compiled dependencies based on `scripts/versions.txt` hash
    - Cache build tools (Meson, Ninja)
    - _Requirements: 10.5_
  
  - [x] 11.3 Configure artifact upload
    - Upload build artifacts using `actions/upload-artifact@v3`
    - Upload logs directory for debugging
    - Upload verification report
    - _Requirements: 4.3_
  
  - [x] 11.4 Add error handling and status reporting
    - Ensure workflow fails if any build step fails
    - Upload logs even on failure
    - Add build status badge to README
    - _Requirements: 4.4, 9.1_

- [ ] 12. Implement error handling and logging
  - [x] 12.1 Add comprehensive error handling to all scripts
    - Check exit codes after every command
    - Validate file existence before proceeding
    - Add retry logic for network downloads (up to 3 attempts)
    - Log full error output to `logs/errors.log`
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 2.5_
  
  - [x] 12.2 Implement structured logging
    - Add log level prefixes: `[INFO]`, `[WARN]`, `[ERROR]`
    - Include timestamps in log format: `[2025-01-15 10:30:45]`
    - Create per-library log files: `build-<library>-<target>.log`
    - _Requirements: 9.2, 9.3, 9.5_

- [ ] 13. Create documentation and README
  - [x] 13.1 Write comprehensive README.md
    - Document prerequisites (Xcode, macOS version)
    - Provide usage instructions for local builds
    - Explain GitHub Actions workflow
    - Document integration steps for iOS apps
    - Add troubleshooting section
    - _Requirements: 4.1, 8.3_
  
  - [x] 13.2 Create integration guide
    - Write `docs/INTEGRATION.md` with step-by-step instructions
    - Provide sample Xcode project configuration
    - Document linking flags and framework search paths
    - Include code examples for initializing MPV
    - _Requirements: 6.1, 6.2_

- [ ] 14. Final integration and end-to-end testing
  - [x] 14.1 Create sample iOS app for testing
    - Create minimal iOS app that links against built library
    - Initialize MPV and verify library loads correctly
    - Test on both iOS device and simulator
    - _Requirements: 1.1, 1.2, 3.1, 3.2_
  
  - [ ]* 14.2 Run full end-to-end test suite
    - Execute complete build pipeline on GitHub Actions
    - Download artifacts and test in sample app
    - Verify all architectures and targets work correctly
    - _Requirements: 1.5, 3.4, 7.1, 7.2_

- [x] 15. Final checkpoint - Complete system validation
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation at key milestones
- All scripts use Bash/Shell scripting language
- Build system is modular to allow independent testing and debugging
- Focus on Infrastructure as Code - no property-based testing needed
