// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LibMpv-iOS",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "Libmpv",
            targets: ["Libmpv"]
        )
    ],
    targets: [
        .target(
            name: "Libmpv",
            dependencies: [],
            cSettings: [
                .headerSearchPath("Sources/Libmpv/include"),
                .unsafeFlags([
                    "-fobjc-arc",
                    "-fmodules"
                ])
            ],
            linkerSettings: [
                .linkedLib("z"),
                .linkedLib("bz2"),
                .linkedLib("resolv"),
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .unsafeFlags([
                    "-L./lib",
                    "-lmpv",
                    "-lswresample",
                    "-lavformat",
                    "-lavcodec",
                    "-lavutil",
                    "-lass",
                    "-lfreetype",
                    "-lharfbuzz",
                    "-lfribidi",
                    "-luchardet"
                ])
            ]
        ),
        .testTarget(
            name: "MPVScreenshotTests",
            dependencies: [
                "Libmpv"
            ],
            path: "Tests",
            cSettings: [
                .headerSearchPath("../Sources/Libmpv/include")
            ],
            resources: [
                .process("Info.plist")
            ]
        )
    ]
)