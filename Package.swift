// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "libmpv-ios",
    platforms: [
        .iOS(.v13),
        .macOS(.v11)
    ],
    products: [
        // libmpv — 视频播放器核心 (需要 Libffmpeg 作为依赖)
        .library(
            name: "Libmpv",
            targets: ["LibmpvWrapper"]
        ),
        // libffmpeg — 音视频编解码库 (FFmpeg + dav1d, 可独立使用)
        .library(
            name: "Libffmpeg",
            targets: ["LibffmpegWrapper"]
        ),
    ],
    targets: [
        // ========== Libmpv: mpv 播放器核心 ==========
        .binaryTarget(
            name: "LibmpvBinary",
            url: "https://github.com/roverlab/libmpv-ios/releases/download/v0.1.73/Libmpv.xcframework.zip",
            checksum: "c1e686bc15348d77db78430cfa01f1f243d32d51634b9ff9296e4233bbcf2ffd"
        ),
        .target(
            name: "LibmpvWrapper",
            dependencies: [
                "LibmpvBinary",
                "LibffmpegBinary",   // libmpv 依赖 libffmpeg 提供编解码能力
            ],
            path: "Sources/LibmpvWrapper",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("VideoToolbox"),
                // Metal 是 MoltenVK/Vulkan/gpu-next 工作的必需依赖
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),      // CoreAnimation，MoltenVK 需要
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOSurface"),       // MoltenVK 需要
                .linkedLibrary("bz2"),
                .linkedLibrary("z"),
                .linkedLibrary("iconv"),
                .linkedLibrary("c++"),              // libc++ 是必需的
            ]
        ),

        // ========== Libffmpeg: FFmpeg 编解码库 ==========
        .binaryTarget(
            name: "LibffmpegBinary",
            url: "https://github.com/roverlab/libmpv-ios/releases/download/v0.1.73/Libffmpeg.xcframework.zip",
            checksum: "f11788fdbd2101b0053521b16fe155a10629966ce57c9ead091495898c7e1677"  // 需要触发 release 工作流后更新
        ),
        .target(
            name: "LibffmpegWrapper",
            dependencies: ["LibffmpegBinary"],
            path: "Sources/LibffmpegWrapper",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox"),
                .linkedLibrary("bz2"),
                .linkedLibrary("z"),
                .linkedLibrary("iconv"),
            ]
        ),
    ]
)