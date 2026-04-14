# Libmpv for iOS

[![Build](https://github.com/roverlab/libmpv-test/actions/workflows/build-ios.yml/badge.svg)](https://github.com/roverlab/libmpv-test/actions/workflows/build-ios.yml)
[![Release](https://img.shields.io/github/v/release/roverlab/libmpv-test)](https://github.com/roverlab/libmpv-test/releases)
[![Platform](https://img.shields.io/badge/platform-iOS%2013%2B%20-lightgrey)](https://www.apple.com/ios/)

预编译的 [libmpv](https://github.com/mpv-player/mpv) iOS 静态库，通过 Swift Package Manager 分发。

## 安装

### Xcode

**File → Add Packages…**，输入仓库地址：

```
https://github.com/roverlab/libmpv-test
```

选择 `main` 分支，点击 **Add Package**。

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/roverlab/libmpv-test", branch: "main")
]
```

> 无需手动配置链接器，所有系统依赖（AVFoundation、AudioToolbox、CoreMedia、CoreVideo、VideoToolbox、bz2、z、iconv）通过 wrapper target 自动链接。

## 使用

```swift
import Libmpv

// 创建实例
let mpv = mpv_create()
mpv_set_option_string(mpv, "vo", "gpu")
mpv_set_option_string(mpv, "gpu-context", "moltenvk")
mpv_initialize(mpv)

// 播放视频
if let path = Bundle.main.path(forResource: "video", ofType: "mp4") {
    mpv_command_string(mpv, "loadfile \"\(path)\"")
}

// 销毁
mpv_terminate_destroy(mpv)
```

## 包含的库

| 库 | 版本 | 说明 |
|---|------|------|
| mpv | 0.39.0 | 视频播放引擎 |
| FFmpeg | 7.0 | 媒体处理 |
| libplacebo | 6.338.2 | GPU 渲染 |
| libass | 0.17.3 | 字幕渲染 |
| freetype | 2.13.2 | 字体渲染 |
| harfbuzz | 8.4.0 | 文字排版 |
| fribidi | 1.0.16 | 双向文本 |

> 版本定义见 [scripts/download.sh](scripts/download.sh)

## 架构支持

| 架构 | 平台 | 状态 |
|------|------|------|
| arm64 | iOS 设备 | ✅ |
| arm64 | iOS 模拟器 (Apple Silicon) | ✅ |

## 从源码构建

### 前置要求

- macOS + Xcode 15+
- Homebrew：`pkg-config nasm meson python@3.13`

### 构建步骤

```bash
git clone https://github.com/roverlab/libmpv-test.git
cd libmpv-test

# 下载源码
./scripts/download.sh

# 编译（设备 + 模拟器）
./scripts/build.sh -e distribution   # arm64 device
./scripts/build.sh -e simulator      # arm64-simulator

# 创建 XCFramework
mkdir -p include_temp/Libmpv
cp scratch/arm64/include/mpv/*.h include_temp/Libmpv/

xcodebuild -create-xcframework \
  -library scratch/arm64/lib/libmpv_full.a \
  -headers include_temp \
  -library scratch/arm64-simulator/lib/libmpv_full.a \
  -headers include_temp \
  -output lib/Libmpv.xcframework \
  -allow-internal-distribution
```

## CI 流水线

- **build-ios** — 推送或手动触发，编译 FFmpeg（缓存）→ fribidi → libmpv（含 subprojects）→ 打包 XCFramework → 测试
- **release** — 手动触发，从最新 build 下载 XCFramework → 创建 GitHub Release → 更新 Package.swift checksum

## License

本项目底层依赖遵循各自许可：

- [mpv](https://github.com/mpv-player/mpv)：LGPL v2.1+ / GPL v2+
- [FFmpeg](https://ffmpeg.org/)：LGPL v2.1+ / GPL v2+
- 其他子项目：ISC / FTL / MIT / LGPL 等

完整 API 文档参考 [mpv manual](https://mpv.io/manual/master/)。

## Vulkan (MoltenVK)

This repository builds Vulkan on Apple platforms via MoltenVK. The build script
compiles MoltenVK from source (no prebuilt binaries) and generates a local
`vulkan.pc` so `mpv` can link against `MoltenVK.framework`.

When using libmpv, set:

```swift
mpv_set_option_string(mpv, "vo", "gpu")
mpv_set_option_string(mpv, "gpu-context", "moltenvk")
```
