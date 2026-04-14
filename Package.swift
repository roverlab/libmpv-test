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
            url: "https://github.com/roverlab/libmpv-test/releases/download/v0.1.58/Libmpv.xcframework.zip",
            checksum: "4475195b87121215c62d2cee56945361f87dfc246f6002f0d52d193ca57ba069"
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