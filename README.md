# libmpv-ios

[![Build](https://github.com/roverlab/libmpv-ios/actions/workflows/build-ios.yml/badge.svg)](https://github.com/roverlab/libmpv-ios/actions/workflows/build-ios.yml)
[![Release](https://img.shields.io/github/v/release/roverlab/libmpv-ios)](https://github.com/roverlab/libmpv-ios/releases)
[![Platform](https://img.shields.io/badge/platform-iOS%2013%2B-lightgrey)](https://www.apple.com/ios/)

预编译的 [libmpv](https://github.com/mpv-player/mpv) iOS 静态库，通过 Swift Package Manager 分发。

## 特性

- **Vulkan/MoltenVK 支持** - 通过 MoltenVK 实现跨平台 Vulkan 渲染
- **硬件加速** - VideoToolbox 解码、AudioToolbox 音频处理
- **现代渲染** - libplacebo GPU 渲染管线，支持 HDR、色调映射等高级特性
- **AV1 支持** - 内置 dav1d AV1 解码器
- **SPM 分发** - 一键集成，无需手动配置链接器

## 安装

### Xcode

**File → Add Packages…**，输入仓库地址：

```
https://github.com/roverlab/libmpv-ios
```

选择 `main` 分支或指定版本，点击 **Add Package**。

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/roverlab/libmpv-ios", from: "0.1.60")
]
```


## Demo

项目包含 iOS Demo，展示 libmpv 的完整使用方式：

```
Demo/Demo-iOS/
├── Demo-iOS.xcodeproj/      # Xcode 工程文件
└── Demo-iOS/                # 源码目录
    ├── Player/
    │   ├── Metal/           # Metal 渲染示例
    │   │   ├── MetalLayer.swift
    │   │   ├── MPVMetalPlayerView.swift
    │   │   └── MPVMetalViewController.swift
    │   ├── OpenGL/          # OpenGL 渲染示例
    │   │   ├── MPVPlayerView.swift
    │   │   └── MPVViewController.swift
    │   ├── MPVPlayerDelegate.swift
    │   └── MPVProperty.swift
    ├── ContentView.swift
    └── Demo_iOSApp.swift
```

打开 `Demo/Demo-iOS/Demo-iOS.xcodeproj` 即可运行。

## 包含的库

| 库 | 版本 | 说明 |
|---|------|------|
| mpv | 0.41.0 | 视频播放引擎 |
| FFmpeg | 8.1 | 媒体处理框架 |
| libplacebo | 7.360.1 | GPU 渲染管线 |
| libass | 0.17.3 | ASS/SSA 字幕渲染 |
| freetype | 2.13.2 | 字体渲染 |
| harfbuzz | 8.4.0 | 文字整形引擎 |
| fribidi | 1.0.16 | 双向文本处理 |
| dav1d | 1.5.3 | AV1 解码器 |
| shaderc | 2026.1 | GLSL/SPIR-V 编译器 |
| MoltenVK | 1.4.1 | Vulkan 实现 |

> 版本定义见各构建脚本：[mpv-build.sh](scripts/components/mpv-build.sh)、[ffmpeg-build.sh](scripts/components/ffmpeg-build.sh)

## 平台与架构支持

| 平台 | 架构 | 状态 |
|------|------|------|
| iOS 设备 | arm64 | ✅ |
| iOS 模拟器 (Apple Silicon) | arm64 | ✅ |

## Vulkan (MoltenVK) 配置

本项目通过 MoltenVK 在 Apple 平台上实现 Vulkan 支持。使用时需设置：

```swift
mpv_set_option_string(mpv, "vo", "gpu")
mpv_set_option_string(mpv, "gpu-context", "moltenvk")
```

或使用 libplacebo 的 GPU-next 渲染器：

```swift
mpv_set_option_string(mpv, "vo", "gpu-next")
mpv_set_option_string(mpv, "gpu-context", "moltenvk")
```

MoltenVK 依赖以下系统框架（已自动链接）：
- Metal
- QuartzCore (CoreAnimation)
- IOSurface
- CoreFoundation

## CI/CD 流水线

| 工作流 | 触发条件 | 说明 |
|--------|----------|------|
| `build-ios.yml` | 推送 tag / 手动触发 | 编译 dav1d → FFmpeg → shaderc → libmpv → 创建 XCFramework |
| `release.yml` | 手动触发 | 从最新构建创建 Release，更新 Package.swift checksum |

### 构建缓存

CI 使用 GitHub Actions 缓存加速构建：
- FFmpeg 缓存 key: `ffmpeg-v8.1-ios-static`
- shaderc 缓存 key: `shaderc-v2026.1-ios-static`

## 项目结构

```
libmpv-ios/
├── Package.swift              # SPM 包定义
├── Sources/
│   └── LibmpvWrapper/        # Swift wrapper，自动链接系统框架
├── Demo/
│   └── Demo-iOS/             # iOS 演示应用
├── scripts/
│   ├── build.sh              # 主构建脚本
│   └── components/
│       ├── dav1d-build.sh    # AV1 解码器
│       ├── ffmpeg-build.sh   # FFmpeg 构建
│       ├── shaderc-build.sh  # SPIR-V 编译器
│       ├── mpv-build.sh      # libmpv + subprojects
│       └── moltenvk-context.patch  # MoltenVK 支持补丁
└── .github/workflows/        # CI 配置
```

## 相关项目

- [MPVKit](https://github.com/mpvkit/MPVKit) - 完整的 mpv iOS/macOS 封装
- [libmpv-native-ios](https://github.com/mpv-player/mpv) - mpv 官方

## 许可证

### 编译配置

本项目采用 **LGPL v2.1+** 许可证模式编译，关键配置如下：

- **mpv**: `-Dgpl=false` (LGPL 模式，不包含 GPL 特性)
- **FFmpeg**: LGPL 配置，启用 libdav1d、libplacebo、libshaderc、libvulkan

> LGPL 模式允许将库作为动态链接库使用于闭源商业应用中。若需 GPL 特性（如 libx264），需自行修改构建脚本。

### 依赖库许可证

| 库 | 许可证 | 说明 |
|---|--------|------|
| mpv | LGPL v2.1+ | 视频播放引擎 |
| FFmpeg | LGPL v2.1+ | 媒体处理框架 |
| libplacebo | LGPL v2.1+ | GPU 渲染管线 |
| libass | ISC | ASS/SSA 字幕渲染 |
| freetype | FTL / GPL | 字体渲染 |
| harfbuzz | MIT | 文字整形引擎 |
| fribidi | LGPL v2.1+ | 双向文本处理 |
| dav1d | BSD 2-Clause | AV1 解码器 |
| shaderc | Apache 2.0 | GLSL/SPIR-V 编译器 |
| MoltenVK | Apache 2.0 | Vulkan 实现 |
| vulkan-headers | Apache 2.0 | Vulkan API 头文件 |

### 使用注意

1. **LGPL 合规**: 使用本库的闭源应用需支持库的替换（动态链接或静态链接+提供目标文件）
2. **FTL 许可证**: freetype 使用 FreeType License，兼容 LGPL，但 GPL 项目需注意
3. **Apache 2.0**: MoltenVK、shaderc、vulkan-headers 为宽松许可证，无特殊限制

完整 API 文档参考 [mpv manual](https://mpv.io/manual/master/)。

## 贡献

欢迎提交 Issue 和 Pull Request！
