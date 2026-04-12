// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Libmpv",
    platforms: [
        .iOS(.v13),
        .macOS(.v11)
    ],
    products: [
        // 用户通过此产品使用 libmpv — 自动链接所有系统依赖
        .library(
            name: "Libmpv",
            targets: ["LibmpvWrapper"]
        )
    ],
    targets: [
        // 内部二进制目标（不直接暴露给用户）
        .binaryTarget(
            name: "LibmpvBinary",
            url: "https://github.com/roverlab/libmpv-test/releases/download/v0.1.29/Libmpv.xcframework.zip",
            checksum: "1857ee9eea56d5dd2d65097062fc178b72a10c76f4c2daf8bb2bc29a4d24ec44"
        ),
        // 包装层：负责自动链接系统框架和库
        // 用户 import Libmpv 时，linkerSettings 会自动传播到用户的 target
        .target(
            name: "LibmpvWrapper",
            dependencies: ["LibmpvBinary"],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("VideoToolbox"),
                .linkedLibrary("bz2"),
                .linkedLibrary("z"),
                .linkedLibrary("iconv"),
            ],
            path: "Sources/LibmpvWrapper"
        )
    ]
)
