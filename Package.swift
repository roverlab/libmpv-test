// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Libmpv",
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
            url: "https://github.com/roverlab/libmpv-test/releases/download/v0.1.53/Libmpv.xcframework.zip",
            checksum: "65cbc9f32e6d7e599f207dff948a9d036e21353be4e99d98b79eca567344f525"
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
                .linkedLibrary("bz2"),
                .linkedLibrary("z"),
                .linkedLibrary("iconv"),
            ]
        )
    ]
)