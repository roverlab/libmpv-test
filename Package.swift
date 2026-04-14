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
            url: "https://github.com/roverlab/libmpv-test/releases/download/v0.1.57/Libmpv.xcframework.zip",
            checksum: "ae440f98e5b824d8124b55415abc686d66591c51fb5d30e7c39e95f1d5b62f1e"
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