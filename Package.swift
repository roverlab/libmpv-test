// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "libmpv-ios",
    platforms: [
        .iOS(.v13),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "Libmpv",
            targets: ["LibmpvWrapper"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "LibmpvBinary",
            url: "https://github.com/roverlab/libmpv-ios/releases/download/v0.1.66/Libmpv.xcframework.zip",
            checksum: "71d3c3d5599cecd880dcb1fcadc0a2ba1a6a9e6f6a0882196114a5b01894b209"
        ),
        .target(
            name: "LibmpvWrapper",
            dependencies: ["LibmpvBinary"],
            path: "Sources/LibmpvWrapper",  // ← path 放在前面
            linkerSettings: [                // ← linkerSettings 放在后面
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
        )
    ]
)